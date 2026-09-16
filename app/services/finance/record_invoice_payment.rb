module Finance
  # Le virement qui paie une facture d'achat (epic #240, phase 4).
  #
  # Affecter la ligne bancaire sortante sur les dettes fournisseurs (`440000`)
  # avec la FACTURE en `document` et son tiers sur l'allocation. C'est ce lien
  # qui fait passer la facture en `paid` — via `PurchaseInvoices::RefreshPayment`,
  # déclenché par le `after_commit` de `CashAllocation`. Rien n'est coché ici :
  # le paiement est un rapprochement (décision 4).
  #
  # DÉCISION 4, l'autre moitié : une dépense couverte par une facture
  # enregistrée ne s'affecte plus directement sur la charge — la charge est
  # déjà passée au journal des achats. L'affecter une seconde fois sur le
  # compte de charge la compterait deux fois.
  class RecordInvoicePayment < ServiceBase
    class NotPayable < StandardError; end
    class WrongDirection < StandardError; end
    class TooMuch < StandardError; end
    class MissingAccount < StandardError; end

    SUPPLIER_CODE = "440000".freeze

    def initialize(purchase_invoice:, cash_entry:, amount_cents: nil, whodunnit: nil)
      @invoice = purchase_invoice
      @entry = cash_entry
      @amount_cents = amount_cents&.to_i&.abs
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { purchase_invoice: @invoice&.id }) { record }
    def run! = record

    private

    def record
      raise NotPayable, "Aucune facture à payer." if @invoice.blank?
      unless @invoice.to_pay?
        raise NotPayable,
              "Seule une facture « À payer » se rapproche — celle-ci est #{@invoice.status_label.downcase}."
      end
      raise WrongDirection, "Une facture se paie depuis une ligne SORTANTE." unless @entry.amount_cents.negative?

      du = @invoice.remaining_cents
      raise NotPayable, "Cette facture est déjà entièrement rapprochée." unless du.positive?

      # Sans montant explicite on solde ce qui reste, dans la limite de ce que
      # la ligne peut encore porter : un virement groupé paie plusieurs factures.
      montant = @amount_cents || [du, @entry.remaining_cents.abs].min
      if montant > du
        raise TooMuch,
              "Cette facture n'attend que #{Money.new(du, 'EUR').format} — " \
              "en affecter #{Money.new(montant, 'EUR').format} la surpaierait."
      end

      PaperTrail.request(whodunnit: @whodunnit || "invoice_payment") do
        ApplicationRecord.transaction do
          @entry.lock!

          @entry.cash_allocations.create!(
            general_account: supplier_account,
            legal_entity: @invoice.legal_entity,
            third_party: @invoice.third_party,
            document: @invoice,
            amount_cents: -montant,
            label: "Paiement #{@invoice.payable_label}"
          )

          Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: @whodunnit).run! if @entry.reload.fully_allocated?
        end
      end

      @invoice.reload
    end

    def supplier_account
      @supplier_account ||= GeneralAccount.find_by(code: SUPPLIER_CODE) ||
                            raise(MissingAccount,
                                  "Le compte des dettes fournisseurs #{SUPPLIER_CODE} n'existe pas — " \
                                  "lance `rake accounting:seed_reference`.")
    end
  end
end
