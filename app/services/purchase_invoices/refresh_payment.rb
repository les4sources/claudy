module PurchaseInvoices
  # Le paiement d'une facture est un RAPPROCHEMENT (epic #240, décision 4).
  #
  # On ne coche pas « payée » : on constate que les lignes de trésorerie
  # affectées sur le `440000` avec cette facture en `document` couvrent son
  # total. Une case cochée à la main finit toujours par mentir ; un
  # rapprochement, non.
  #
  # Et il fonctionne dans les deux sens : si on défait l'affectation, la facture
  # redevient « À payer ». Un état qui ne sait que monter est un état faux.
  class RefreshPayment < ServiceBase
    def initialize(purchase_invoice:)
      @invoice = purchase_invoice
    end

    def run = catch_error(context: { purchase_invoice: @invoice&.id }) { refresh }
    def run! = refresh

    private

    def refresh
      return @invoice if @invoice.blank?
      return @invoice unless %w[to_pay paid].include?(@invoice.status)

      couvert = @invoice.cash_allocations.sum(:amount_cents).abs

      if couvert >= @invoice.total_cents && @invoice.total_cents.positive?
        return @invoice if @invoice.paid?

        @invoice.update_columns(status: "paid", paid_on: derniere_date || Date.current)
      elsif @invoice.paid?
        @invoice.update_columns(status: "to_pay", paid_on: nil)
      end

      @invoice.reload
    end

    def derniere_date
      @invoice.cash_allocations.includes(:cash_entry).map { |a| a.cash_entry&.entry_date }.compact.max
    end
  end
end
