module Finance
  # L'encaissement d'une facture de vente depuis une ligne bancaire entrante
  # (epic #240, phase 6).
  #
  # Ce service NE CHANGE PAS la comptabilité des recettes : il ventile le séjour
  # exactement comme le fait déjà l'action « Ventiler ce séjour » sur
  # « À affecter », avec `Finance::VentilateStay`. **Aucune écriture de vente
  # n'est générée** (décision 8) — la recette est comptabilisée une seule fois,
  # par cette ventilation.
  #
  # La seule chose qui change : les allocations portent la FACTURE en `document`
  # plutôt que le séjour. C'est ce qui fait basculer la facture en « payée »,
  # par le rapprochement de `SalesInvoices::RefreshPayment` — jamais par une
  # case cochée.
  class RecordSalesInvoicePayment < ServiceBase
    class WrongDirection < StandardError; end
    class AlreadyPaid < StandardError; end
    class NoVentilableSource < StandardError; end

    def initialize(sales_invoice:, cash_entry:, whodunnit: nil)
      @invoice = sales_invoice
      @entry = cash_entry
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { sales_invoice: @invoice&.id }) { record }
    def run! = record

    private

    def record
      raise WrongDirection, "Une facture de vente s'encaisse depuis une ligne ENTRANTE." unless @entry.amount_cents.positive?
      raise AlreadyPaid, "La facture #{@invoice.number} est déjà payée." if @invoice.paid?

      stay = @invoice.stay_sources.first
      if stay.blank?
        raise NoVentilableSource,
              "La facture #{@invoice.number} ne facture aucun séjour : sa ventilation en recettes " \
              "n'est pas automatisable, affecte la ligne à la main."
      end

      lignes = []
      entite = @entry.cash_account.legal_entity

      PaperTrail.request(whodunnit: @whodunnit || "sales_invoice_payment") do
        ApplicationRecord.transaction do
          @entry.lock!

          # La ventilation se calcule APRÈS le verrou : calculée avant, elle
          # totaliserait un montant que la ligne n'a peut-être plus.
          lignes = Finance::VentilateStay.new(stay: stay, amount_cents: @entry.reload.amount_cents).run!

          lignes.each do |ligne|
            @entry.cash_allocations.create!(
              general_account: ligne.general_account,
              team: ligne.team,
              legal_entity: entite,
              amount_cents: ligne.amount_cents,
              # LA FACTURE, pas le séjour : c'est ce lien qui fait basculer la
              # facture en « payée » au rapprochement.
              document: @invoice,
              label: ligne.label
            )
          end

          # Le même apprentissage d'IBAN que la ventilation directe : c'est lui
          # qui fera que le prochain virement de ce client se rapprochera tout
          # seul (`MatchSalesInvoices`, indice IBAN).
          CustomerBankAccount.remember!(customer: stay.customer, iban: @entry.counterparty_iban,
                                        holder_name: @entry.counterparty_name)

          if @entry.reload.fully_allocated?
            Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: @whodunnit).run!
          end
        end
      end

      @invoice.reload
      lignes
    end
  end
end
