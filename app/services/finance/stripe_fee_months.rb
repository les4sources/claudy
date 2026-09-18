module Finance
  # Ce que Claudy a compté en frais Stripe, par compte et par mois (epic #240,
  # phase 5), face au justificatif déposé.
  #
  # Le comptage suit la même règle que la page « Coût d'encaissement » : un
  # compte en mode GRAND LIVRE se lit par transaction (`occurred_at`), un compte
  # classique par versement (`arrival_date`). Lire un compte `ledger` par
  # versement donnerait zéro — ce qui n'est pas « rien à payer » mais « on ne
  # regarde pas au bon endroit ».
  class StripeFeeMonths
    Row = Struct.new(:account_key, :label, :month, :basis, :counted_fee_cents, :invoice, keyword_init: true) do
      def declared_fee_cents = invoice&.declared_fee_cents

      # L'écart : déclaré − compté. Positif, Stripe facture plus que ce que
      # Claudy a vu ; négatif, l'inverse. `nil` tant que rien n'est déclaré.
      def gap_cents = invoice&.gap_cents(counted_fee_cents)

      def gap? = gap_cents.present? && !gap_cents.zero?
      def document? = invoice&.document&.attached?
    end

    def initialize(from:, to:)
      @from = from
      @to = to
    end

    # Une ligne par compte et par mois de la période, du plus récent au plus
    # ancien. Les mois sans le moindre frais compté ET sans justificatif sont
    # écartés : une grille de mois vides n'apprend rien.
    def rows
      @rows ||= months.flat_map { |month| StripeService::ACCOUNTS.keys.map { |key| row_for(key.to_s, month) } }
                      .compact
                      .sort_by { |row| [-row.month.to_time.to_i, row.label] }
    end

    def months
      @months ||= begin
        first = @from.beginning_of_month
        last = @to.beginning_of_month
        list = []
        current = first
        while current <= last
          list << current
          current = current.next_month
        end
        list
      end
    end

    private

    def row_for(account_key, month)
      counted = counted_fee_cents(account_key, month)
      invoice = StripeFeeInvoice.find_for(account_key, month)
      return nil if counted.zero? && invoice.nil?

      Row.new(account_key: account_key, label: StripeService.label_for(account_key), month: month,
              basis: ledger?(account_key) ? :transaction : :payout,
              counted_fee_cents: counted, invoice: invoice)
    end

    def counted_fee_cents(account_key, month)
      return ledger_fee_cents(account_key, month) if ledger?(account_key)

      StripePayout.for_account(account_key)
                  .where(arrival_date: month..month.end_of_month)
                  .sum(&:fees_cents)
    end

    def ledger_fee_cents(account_key, month)
      scope = StripeBalanceTransaction.for_account(account_key)
                                      .where(occurred_at: month.beginning_of_day..month.end_of_month.end_of_day)
      # Les frais sont NÉGATIFS au grand livre : on les lit en valeur absolue.
      scope.revenue.sum(:fee_cents).abs + scope.costs.sum(:net_cents).abs
    end

    def ledger?(account_key)
      ledger_keys.include?(account_key)
    end

    def ledger_keys
      @ledger_keys ||= CashAccount.stripe_ledger.pluck(:stripe_account_key).compact.map(&:to_s)
    end
  end
end
