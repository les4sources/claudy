module SalesInvoices
  # Le paiement d'une facture de vente est un RAPPROCHEMENT (epic #240,
  # décision 4), exactement comme celui d'une facture d'achat.
  #
  # On ne coche pas « payée » : on constate que les lignes de trésorerie
  # affectées avec cette facture en `document` couvrent son total. Et ça
  # fonctionne dans les deux sens — défaire l'affectation la ramène à « émise ».
  # Un état qui ne sait que monter est un état faux.
  class RefreshPayment < ServiceBase
    def initialize(sales_invoice:)
      @invoice = sales_invoice
    end

    def run = catch_error(context: { sales_invoice: @invoice&.id }) { refresh }
    def run! = refresh

    private

    def refresh
      return @invoice if @invoice.blank?

      couvert = @invoice.cash_allocations.sum(:amount_cents).abs

      if couvert >= @invoice.total_cents && @invoice.total_cents.positive?
        @invoice.update_columns(status: "paid", paid_on: derniere_date || Date.current) unless @invoice.paid?
      elsif @invoice.paid?
        @invoice.update_columns(status: "issued", paid_on: nil)
      end

      @invoice.reload
    end

    def derniere_date
      @invoice.cash_allocations.includes(:cash_entry).filter_map { |a| a.cash_entry&.entry_date }.max
    end
  end
end
