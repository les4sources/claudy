module Stripe
  # Prérempli le montant des justificatifs mensuels des frais Stripe (Michael,
  # 2026-10-19).
  #
  # Stripe n'expose PAS le PDF de sa facture de frais par l'API : il ne se
  # télécharge que du Dashboard. Ce que l'API donne, c'est le détail du solde,
  # transaction par transaction — la source du rapport de solde de Stripe. On y
  # additionne les frais du mois civil (date de la transaction, comme la
  # facture) et on remplit le montant déclaré du mois, quand personne ne l'a
  # encore saisi. Il ne reste qu'à déposer le PDF.
  #
  # Un montant déjà déclaré n'est jamais écrasé : il a été lu sur le PDF, ou
  # relevé une première fois. Aucune écriture comptable, comme le justificatif
  # lui-même. Dry-run par défaut, comme `SyncPayouts`.
  class PrefillFeeInvoices < ServiceBase
    Result = Struct.new(:account_key, :month, :fee_cents, :action, keyword_init: true)

    def initialize(since: nil, until_month: nil, today: Date.current, apply: false, clients: {})
      @today = today
      @until = (until_month || today.prev_month).beginning_of_month
      @since = (since || @until.beginning_of_year).beginning_of_month
      @apply = apply
      @clients = clients
      @messages = []
    end

    attr_reader :messages

    def run!
      results = StripeService::ACCOUNTS.keys.flat_map { |key| prefill_account(key.to_s) }
      { results: results, messages: @messages }
    end

    private

    def prefill_account(account_key)
      months.filter_map do |month|
        next if StripeFeeInvoice.find_for(account_key, month)&.declared_fee_cents

        fee_cents = client_for(account_key).fee_cents(from: month, to: month.next_month)
        next if fee_cents.zero?

        record(account_key, month, fee_cents) if @apply
        Result.new(account_key: account_key, month: month, fee_cents: fee_cents, action: @apply ? :filled : :to_fill)
      end
    rescue StripeService::MissingKey => e
      @messages << e.message
      []
    end

    def record(account_key, month, fee_cents)
      invoice = StripeFeeInvoice.find_for(account_key, month) ||
                StripeFeeInvoice.new(account_key: account_key, period_month: month)
      invoice.update!(declared_fee_cents: fee_cents, declared_fee_fetched_at: Time.current)
    end

    # Les mois TERMINÉS seulement : le mois en cours n'a pas fini d'accumuler
    # des frais, et un montant relevé trop tôt ne serait plus jamais corrigé.
    def months
      @months ||= begin
        last = [@until, @today.prev_month.beginning_of_month].min
        list = []
        current = @since
        while current <= last
          list << current
          current = current.next_month
        end
        list
      end
    end

    def client_for(account_key)
      @clients[account_key] ||= Client.new(account_key)
    end

    # L'adaptateur réel, isolé comme celui de `SyncPayouts` : le service se
    # vérifie sans réseau et sans clé.
    class Client
      # Les frais facturés à part (abonnements, Radar…) sont des transactions
      # à part entière, de montant négatif et sans `fee`.
      FEE_TYPES = %w[stripe_fee tax_fee].freeze

      def initialize(account_key)
        @service = StripeService.for(account_key)
      end

      # Les frais des transactions créées dans [from, to[ : la commission de
      # chaque paiement (`fee`, taxes sur les frais comprises), plus les frais
      # facturés à part.
      def fee_cents(from:, to:)
        params = { created: { gte: from.beginning_of_day.to_i, lt: to.beginning_of_day.to_i }, limit: 100 }
        ::Stripe::BalanceTransaction.list(params, @service.request_options).auto_paging_each.sum do |transaction|
          FEE_TYPES.include?(transaction.type) ? transaction.net.to_i.abs : transaction.fee.to_i
        end
      end
    end
  end
end
