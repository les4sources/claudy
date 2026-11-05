module Finance
  # Relier à sa facture un paiement déjà passé au 440000 sans elle (Michael,
  # 2026-11-05, VOO) : la domiciliation du 15/10 avait été affectée au 440000
  # par la règle « Orange Belgium », la facture restait « À payer ».
  #
  # Le compte et le montant ne changent pas : c'est le même 440000. Ce qui
  # change, c'est la PIÈCE (la facture, qui passe alors « Payée » par
  # `PurchaseInvoices::RefreshPayment`) et le TIERS de l'affectation, qui entre
  # dans l'écriture — sans lui, la balance tiers du fournisseur garderait sa
  # dette ouverte et un paiement sans nom traînerait à côté.
  #
  # Une ligne comptabilisée ne se réécrit pas en place : quand le tiers doit
  # changer, son écriture est contre-passée puis la ligne se recomptabilise
  # (comme `ReallocateCashEntry`), tout ou rien. Sur un mois arrêté, on ne
  # touche pas à l'écriture : la pièce seule se relie (`relink_document!`),
  # et le tiers reste à poser par une écriture de correction si le comptable
  # le demande.
  class LinkOrphanPayment < ServiceBase
    class Refused < StandardError; end

    Result = Struct.new(:invoice, :cash_entry, :reposted, keyword_init: true)

    def initialize(purchase_invoice:, allocation:, whodunnit: nil)
      @invoice = purchase_invoice
      @allocation = allocation
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { purchase_invoice: @invoice&.id, allocation: @allocation&.id }) { link }
    def run! = link

    private

    def link
      garde_fous!
      entry = @allocation.cash_entry
      reposted = false

      PaperTrail.request(whodunnit: @whodunnit || "invoice_payment") do
        ApplicationRecord.transaction do
          entry.lock!

          if tiers_a_poser? && reecrivable?(entry)
            etait_passee = entry.posted?
            Accounting::UnpostCashEntry.new(cash_entry: entry, whodunnit: @whodunnit).run! if etait_passee
            @allocation.reload.update!(document: @invoice, third_party: @invoice.third_party, label: libelle)
            if etait_passee && entry.reload.fully_allocated?
              Accounting::PostCashEntry.new(cash_entry: entry, whodunnit: @whodunnit).run!
              reposted = true
            end
          else
            @allocation.relink_document!(@invoice)
          end
        end
      end

      Result.new(invoice: @invoice.reload, cash_entry: entry.reload, reposted: reposted)
    rescue Accounting::UnpostCashEntry::ClosedFiscalYear => e
      raise Refused, e.message
    end

    def garde_fous!
      raise Refused, "Aucune facture à relier." if @invoice.blank? || @allocation.blank?
      raise Refused, "Seule une facture « À payer » se relie à un paiement." unless @invoice.to_pay? && !@invoice.credit_note?

      candidate = OrphanSupplierPayments.new(invoices: [@invoice]).for(@invoice)
                                        .find { |c| c.allocation.id == @allocation.id }
      return if candidate

      raise Refused, "Ce paiement ne peut pas solder cette facture : il faut une affectation 440000 sans pièce, " \
                     "de la même structure, sans autre tiers, du montant exact qui reste dû " \
                     "(#{Money.new(@invoice.remaining_cents, 'EUR').format})."
    end

    def tiers_a_poser? = @allocation.third_party_id != @invoice.third_party_id

    # Ni mois arrêté, ni exercice clôturé : l'écriture peut être refaite.
    def reecrivable?(entry)
      return true unless entry.posted?
      return false if MonthClosing.closed?(entry.entry_date)

      JournalEntry.where(source_type: "CashEntry", source_id: entry.id).includes(:fiscal_year).none? { |e| e.fiscal_year.closed? }
    end

    def libelle = "Paiement #{@invoice.payable_label}"
  end
end
