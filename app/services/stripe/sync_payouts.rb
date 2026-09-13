module Stripe
  # Lit un compte Stripe (issues #187 et #250).
  #
  # Le client est INJECTABLE, et ce n'est pas seulement pour les tests :
  # interroger le compte de production, ou demander les clés d'un second compte,
  # n'est pas une décision qui se prend au fil d'une implémentation. Le service
  # est donc écrit contre une interface, vérifié sur des jeux de données
  # construits d'après le format documenté, et sa première exécution réelle est
  # un geste humain avec la clé sous les yeux.
  #
  # Deux lectures, selon le mode du compte de trésorerie (epic #250) :
  #
  # `per_payout` — un versement et ses transactions. C'est ce que Stripe autorise
  # quand les versements sont AUTOMATIQUES. Inchangé depuis #187.
  #
  # `ledger` — le solde Stripe tenu comme un compte de trésorerie. C'est la seule
  # lecture possible quand les versements sont MANUELS : Stripe refuse alors
  # `BalanceTransaction.list(payout: …)`, parce que le montant viré est choisi
  # librement et ne correspond à aucune liste de ventes.
  class SyncPayouts < ServiceBase
    def initialize(account_key: :claudy, since: Date.current.beginning_of_year, apply: false, client: nil)
      @account_key = account_key.to_sym
      @since = since
      @apply = apply
      @client = client
      @messages = []
    end

    def run
      catch_error(context: { account: @account_key }) { sync }
    end

    def run!
      sync
    end

    private

    def sync
      # Le compte de trésorerie se choisit par sa CLÉ, pas par « le premier de
      # type stripe » : avec deux comptes, les flux de Tranche de Vie
      # atterriraient sur celui de Claudy.
      cash_account = CashAccount.find_by(stripe_account_key: @account_key.to_s) ||
                     CashAccount.where(kind: "stripe", stripe_account_key: nil).first
      if cash_account.nil?
        @messages << "Aucun compte de trésorerie pour le compte Stripe « #{@account_key} » : " \
                     "renseigne `stripe_account_key` sur le compte concerné."
      end

      cash_account&.ledger? ? sync_ledger(cash_account) : sync_per_payout(cash_account)
    end

    # ------------------------------------------------------------------ per_payout

    def sync_per_payout(cash_account)
      payouts = client.payouts(since: @since)

      # Un versement manuel ne se lit pas par ses transactions : Stripe refuse le
      # filtre. Ce n'est pas une exception à faire remonter au milieu du rake —
      # c'est un compte qui n'est pas dans le bon mode, et on le DIT (décision 3).
      manuels = payouts.select { |payout| payout[:automatic] == false }
      if manuels.any?
        @messages << "#{manuels.size} versement(s) manuel(s) sur ce compte — Stripe refuse d'en " \
                     "lister les transactions. Passe le compte en mode grand livre : " \
                     "`CashAccount.find_by(stripe_account_key: \"#{@account_key}\")" \
                     ".update!(stripe_mode: \"ledger\")`, puis relance."
        return empty_report(mode: "per_payout", payouts: payouts.size)
      end

      created_payouts = 0
      created_transactions = 0
      transactions_lues = 0

      payouts.each do |payout|
        transactions = client.balance_transactions(payout_id: payout[:id])
        transactions_lues += transactions.size

        existant = StripePayout.find_by(account_key: @account_key.to_s, stripe_id: payout[:id])
        next if existant

        # Un versement dont les transactions ne le referment pas n'est pas
        # importé du tout. L'enregistrer puis le sauter à la relance le figerait
        # incomplet pour toujours — et il fausserait le coût d'encaissement.
        composantes = transactions.reject { |t| normalize_kind(t[:type]) == "payout" }
        net = composantes.sum { |t| t[:net].to_i }
        if net != payout[:amount].to_i
          @messages << "Versement #{payout[:id]} ignoré : ses transactions totalisent #{net} " \
                       "pour un net de #{payout[:amount]}. Il en manque."
          next
        end

        created_payouts += 1
        created_transactions += transactions.size
        next unless @apply

        ApplicationRecord.transaction do
          enregistre = create_payout(payout, cash_account)
          transactions.each { |transaction| create_transaction(enregistre, cash_account, transaction) }
        end
      end

      { mode: "per_payout", payouts: payouts.size, transactions: transactions_lues,
        created_payouts: created_payouts, created_transactions: created_transactions,
        created_entries: 0, categories: [], messages: @messages }
    end

    # ---------------------------------------------------------------------- ledger

    def sync_ledger(cash_account)
      payouts = client.payouts(since: @since)
      created_payouts = 0

      payouts.each do |payout|
        next if StripePayout.exists?(account_key: @account_key.to_s, stripe_id: payout[:id])

        created_payouts += 1
        create_payout(payout, cash_account) if @apply
      end

      transactions = client.balance_transactions_since(since: @since)
      created_transactions = 0
      created_entries = 0
      tally = Hash.new { |hash, key| hash[key] = { count: 0, amount_cents: 0 } }

      transactions.each do |attributes|
        kind = normalize_kind(attributes[:type])

        if StripeBalanceTransaction::REVENUE_KINDS.include?(kind)
          cle = attributes[:category].presence
          tally[cle][:count] += 1
          tally[cle][:amount_cents] += attributes[:amount].to_i
        end

        next if StripeBalanceTransaction.exists?(stripe_id: attributes[:id])

        created_transactions += 1
        next unless @apply

        transaction = create_ledger_transaction(cash_account, attributes, kind)
        created_entries += Finance::RecordStripeTransaction.new(transaction: transaction).run!.size
      end

      categories = tally.map do |category, totaux|
        { category: category, count: totaux[:count], amount_cents: totaux[:amount_cents],
          mapped: StripeCategoryMapping.for(@account_key, category).present? }
      end.sort_by { |row| -row[:count] }

      manquantes = categories.reject { |row| row[:mapped] }
      if manquantes.any?
        libelles = manquantes.map { |row| row[:category] || "sans catégorie" }
        @messages << "#{manquantes.size} catégorie(s) sans correspondance : #{libelles.join(', ')}. " \
                     "Crée-les avec `rake stripe:seed_category_mapping ACCOUNT=#{@account_key} " \
                     "CATEGORY=… GENERAL_ACCOUNT=…` — leurs recettes resteront sinon à affecter."
      end

      { mode: "ledger", payouts: payouts.size, transactions: transactions.size,
        created_payouts: created_payouts, created_transactions: created_transactions,
        created_entries: created_entries, categories: categories, messages: @messages }
    end

    # ----------------------------------------------------------------- écritures

    def create_payout(payout, cash_account)
      StripePayout.create!(
        account_key: @account_key.to_s,
        cash_account: cash_account,
        stripe_id: payout[:id],
        amount_cents: payout[:amount],
        arrival_date: payout[:arrival_date],
        status: payout[:status],
        automatic: payout[:automatic],
        currency: (payout[:currency] || "EUR").upcase,
        synced_at: Time.current
      )
    end

    def create_transaction(payout, cash_account, attributes)
      StripeBalanceTransaction.create!(
        stripe_payout: payout,
        cash_account: cash_account,
        account_key: @account_key.to_s,
        stripe_id: attributes[:id],
        kind: normalize_kind(attributes[:type]),
        gross_cents: attributes[:amount].to_i,
        fee_cents: attributes[:fee].to_i,
        net_cents: attributes[:net].to_i,
        payment_id: attributes[:payment_id],
        category: attributes[:category],
        description: attributes[:description],
        available_on: attributes[:available_on],
        occurred_at: attributes[:created]
      )
    end

    # En mode `ledger`, la transaction appartient au COMPTE. Seule la transaction
    # de type `payout` pointe un versement — et c'est ce lien qui fait du
    # versement un virement interne identifiable sur « À affecter ».
    def create_ledger_transaction(cash_account, attributes, kind)
      payout = if kind == "payout" && attributes[:source_id].present?
                 StripePayout.find_by(account_key: @account_key.to_s, stripe_id: attributes[:source_id])
               end

      StripeBalanceTransaction.create!(
        stripe_payout: payout,
        cash_account: cash_account,
        account_key: @account_key.to_s,
        stripe_id: attributes[:id],
        kind: kind,
        gross_cents: attributes[:amount].to_i,
        fee_cents: attributes[:fee].to_i,
        net_cents: attributes[:net].to_i,
        payment_id: attributes[:payment_id],
        category: attributes[:category],
        description: attributes[:description],
        available_on: attributes[:available_on],
        occurred_at: attributes[:created]
      )
    end

    def empty_report(mode:, payouts: 0)
      { mode: mode, payouts: payouts, transactions: 0, created_payouts: 0,
        created_transactions: 0, created_entries: 0, categories: [], messages: @messages }
    end

    def normalize_kind(type)
      valeur = type.to_s
      StripeBalanceTransaction::KINDS.include?(valeur) ? valeur : "other"
    end

    def client
      @client ||= Client.new(@account_key)
    end

    # L'adaptateur réel. Isolé pour que le service reste testable sans réseau et
    # sans clé — et pour que le jour où l'API change, un seul endroit bouge.
    class Client
      def initialize(account_key)
        @service = StripeService.for(account_key)
      end

      # `auto_paging_each` et pas `.data` : Stripe plafonne une page à 100, et un
      # versement de fin de mois en dépasse largement. Une page tronquée
      # donnerait un versement qui ne se referme pas — refusé à l'import, donc
      # invisible, ce qui est le pire des deux mondes.
      #
      # `automatic` dit si Stripe a déclenché le versement lui-même. C'est ce qui
      # permet de refuser proprement un compte manuel resté en mode par
      # versement, plutôt que de buter sur une erreur d'API (epic #250).
      def payouts(since:)
        ::Stripe::Payout.list({ arrival_date: { gte: since.to_time.to_i }, limit: 100 },
                              @service.request_options).auto_paging_each.map do |payout|
          { id: payout.id, amount: payout.amount, currency: payout.currency,
            status: payout.status, automatic: payout.try(:automatic),
            arrival_date: payout.arrival_date ? Time.at(payout.arrival_date).to_date : nil }
        end
      end

      # `expand: data.source` développe la charge derrière chaque transaction :
      # c'est là que vivent les métadonnées posées à l'émission du paiement
      # (`payment_id`, `categorie`). Sans elles, aucune commission de séjour ne
      # peut être ventilée au prorata et tout tombe en frais non affectés.
      def balance_transactions(payout_id:)
        list({ payout: payout_id, limit: 100, expand: ["data.source"] })
      end

      # TOUTES les transactions du solde depuis une date, sans passer par les
      # versements. C'est la seule lecture que Stripe autorise sur un compte à
      # versements manuels — et elle suffit, puisque le solde y est tenu comme un
      # compte de trésorerie.
      def balance_transactions_since(since:)
        list({ created: { gte: since.to_time.to_i }, limit: 100, expand: ["data.source"] })
      end

      private

      def list(params)
        ::Stripe::BalanceTransaction.list(params, @service.request_options)
                                    .auto_paging_each.map { |transaction| serialize(transaction) }
      end

      def serialize(transaction)
        metadata = extract_metadata(transaction)

        { id: transaction.id, type: transaction.type, amount: transaction.amount,
          fee: transaction.fee, net: transaction.net,
          description: transaction.description,
          created: transaction.created ? Time.at(transaction.created) : nil,
          available_on: transaction.try(:available_on) ? Time.at(transaction.available_on).to_date : nil,
          source_id: source_id_for(transaction),
          payment_id: metadata["payment_id"].presence, category: metadata["categorie"].presence }
      end

      # `source` est développé quand on l'a demandé, et reste un identifiant
      # sinon : les deux formes se lisent ici, pour que la transaction d'un
      # versement retrouve son versement.
      def source_id_for(transaction)
        source = transaction.try(:source)
        return nil if source.blank?

        source.is_a?(String) ? source : source.try(:id)
      end

      def extract_metadata(transaction)
        source = transaction.try(:source)
        return {} if source.blank? || !source.respond_to?(:metadata)

        (source.metadata || {}).to_h.transform_keys(&:to_s)
      rescue StandardError
        {}
      end
    end
  end
end
