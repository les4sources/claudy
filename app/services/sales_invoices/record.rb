module SalesInvoices
  # L'enregistrement d'une facture de vente SANS réservation (Michael,
  # 2026-10-30) : un tiers client, des lignes de produit, le PDF, et l'écriture
  # au journal Ventes, ensemble ou pas du tout.
  #
  # Une facture de la file Facturation passe par `Register`, qui ne passe pas
  # d'écriture : sa recette arrive à l'encaissement.
  class Record < ServiceBase
    def initialize(attributes:, document: nil, whodunnit: nil)
      @attributes = attributes.to_h.symbolize_keys
      @document = document
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { number: @attributes[:number] }) { record }
    def run! = record

    def invoice = @invoice

    private

    def record
      PaperTrail.request(whodunnit: @whodunnit || "sales_invoice") do
        ApplicationRecord.transaction do
          @invoice = SalesInvoice.new(@attributes.merge(posting_mode: "on_issue", status: "issued"))
          @invoice.save!
          @invoice.document.attach(@document) if @document.present?

          Accounting::PostSalesInvoice.new(sales_invoice: @invoice, whodunnit: @whodunnit).run!

          RefreshPayment.new(sales_invoice: @invoice).run!
          RefreshPayment.new(sales_invoice: @invoice.credited_invoice).run! if @invoice.credited_invoice
        end
      end

      @invoice.reload
    end
  end
end
