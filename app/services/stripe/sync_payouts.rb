module Stripe
  # Lit les versements d'un compte Stripe et leur détail (issue #187).
  #
  # Le client est INJECTABLE, et ce n'est pas seulement pour les tests :
  # interroger le compte de production, ou demander les clés d'un second compte,
  # n'est pas une décision qui se prend au fil d'une implémentation. Le service
  # est donc écrit contre une interface, vérifié sur des jeux de données
  # construits d'après le format documenté, et sa première exécution réelle est
  # un geste humain avec la clé sous les yeux.
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

      payouts = client.payouts(since: @since)
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
          enregistre = StripePayout.create!(
            account_key: @account_key.to_s,
            cash_account: cash_account,
            stripe_id: payout[:id],
            amount_cents: payout[:amount],
            arrival_date: payout[:arrival_date],
            status: payout[:status],
            currency: (payout[:currency] || "EUR").upcase,
            synced_at: Time.current
          )

          transactions.each { |transaction| create_transaction(enregistre, transaction) }
        end
      end

      { payouts: payouts.size, transactions: transactions_lues,
        created_payouts: created_payouts, created_transactions: created_transactions,
        messages: @messages }
    end

    def create_transaction(payout, attributes)
      StripeBalanceTransaction.create!(
        stripe_payout: payout,
        stripe_id: attributes[:id],
        kind: normalize_kind(attributes[:type]),
        gross_cents: attributes[:amount].to_i,
        fee_cents: attributes[:fee].to_i,
        net_cents: attributes[:net].to_i,
        payment_id: attributes[:payment_id],
        category: attributes[:category],
        description: attributes[:description],
        occurred_at: attributes[:created]
      )
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
      def payouts(since:)
        ::Stripe::Payout.list({ arrival_date: { gte: since.to_time.to_i }, limit: 100 },
                              @service.request_options).auto_paging_each.map do |payout|
          { id: payout.id, amount: payout.amount, currency: payout.currency,
            status: payout.status,
            arrival_date: payout.arrival_date ? Time.at(payout.arrival_date).to_date : nil }
        end
      end

      # `expand: data.source` développe la charge derrière chaque transaction :
      # c'est là que vivent les métadonnées posées à l'émission du paiement
      # (`payment_id`, `categorie`). Sans elles, aucune commission de séjour ne
      # peut être ventilée au prorata et tout tombe en frais non affectés.
      def balance_transactions(payout_id:)
        ::Stripe::BalanceTransaction.list({ payout: payout_id, limit: 100, expand: ["data.source"] },
                                          @service.request_options).auto_paging_each.map do |transaction|
          metadata = extract_metadata(transaction)

          { id: transaction.id, type: transaction.type, amount: transaction.amount,
            fee: transaction.fee, net: transaction.net,
            description: transaction.description,
            created: transaction.created ? Time.at(transaction.created) : nil,
            payment_id: metadata["payment_id"].presence, category: metadata["categorie"].presence }
        end
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
