module SalesInvoices
  # Retirer une facture du registre (Michael, 2026-10-30).
  #
  # Soft-delete : une facture retirée a existé, et son numéro OkiOki aussi. Si
  # elle était comptabilisée, son écriture est contre-passée à sa date
  # (`Unpost`) : les deux restent au grand livre.
  #
  # Refusé tant qu'un encaissement y est rapproché ou qu'une note de crédit la
  # corrige : les retirer d'abord, sinon ils pointeraient une facture absente.
  class Withdraw < ServiceBase
    class Refused < StandardError; end

    def initialize(sales_invoice:, whodunnit: nil)
      @invoice = sales_invoice
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { sales_invoice: @invoice&.id }) { withdraw }
    def run! = withdraw

    private

    def withdraw
      if @invoice.cash_allocations.any?
        raise Refused, "Cette facture porte des affectations bancaires — retire-les d'abord."
      end
      if @invoice.credit_notes.any?
        raise Refused, "Une note de crédit corrige cette facture (#{@invoice.credit_notes.map(&:number).join(', ')}) — retire-la d'abord."
      end

      corrigee = @invoice.credited_invoice

      PaperTrail.request(whodunnit: @whodunnit || "sales_invoice") do
        ApplicationRecord.transaction do
          Unpost.new(sales_invoice: @invoice, whodunnit: @whodunnit).run!
          @invoice.destroy!
          RefreshPayment.new(sales_invoice: corrigee).run! if corrigee
        end
      end

      @invoice
    end
  end
end
