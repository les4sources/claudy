module Finance
  # L'encaissement d'une facture de vente depuis une ligne de trésorerie
  # (epic #240, phase 6 ; toute facture du registre depuis le 2026-10-30).
  #
  # Deux circuits, selon la façon dont la facture est arrivée au grand livre :
  #
  # - `on_payment` (facture d'un séjour) : la ligne ventile le séjour comme
  #   « Ventiler ce séjour » (`Finance::VentilateStay`), les allocations portant
  #   la FACTURE en `document`. C'est cette ventilation qui reconnaît la
  #   recette : aucune écriture de vente n'existe (décision 8).
  # - `on_issue` (facture passée au journal Ventes) : la recette est déjà au
  #   grand livre. La ligne s'affecte sur le `400000` du tiers, avec la facture
  #   en `document` — l'affecter sur un compte 7 compterait la vente deux fois.
  #   Une facture payée en deux virements s'encaisse deux fois, un virement qui
  #   solde deux factures se rapproche de l'une puis de l'autre : sans montant,
  #   on impute ce qui reste dû, dans la limite de ce que la ligne porte encore.
  #   Une note de crédit non imputée se rembourse de même, depuis une ligne
  #   sortante.
  #
  # Le statut payé vient du rapprochement (`SalesInvoices::RefreshPayment`,
  # déclenché par le commit de l'allocation), jamais d'une case cochée.
  class RecordSalesInvoicePayment < ServiceBase
    class WrongDirection < StandardError; end
    class AlreadyPaid < StandardError; end
    class NoVentilableSource < StandardError; end
    class TooMuch < StandardError; end
    class MissingAccount < StandardError; end

    CUSTOMER_CODE = "400000".freeze

    def initialize(sales_invoice:, cash_entry:, amount_cents: nil, whodunnit: nil)
      @invoice = sales_invoice
      @entry = cash_entry
      @amount_cents = amount_cents&.to_i&.abs
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { sales_invoice: @invoice&.id }) { record }
    def run! = record

    private

    def record
      raise AlreadyPaid, "#{@invoice.label} est déjà #{@invoice.status_label.downcase}." if @invoice.paid?

      @invoice.on_issue? ? record_on_customer_account : record_by_ventilation
    end

    def record_on_customer_account
      sortante = @invoice.credit_note?
      if sortante && !@entry.amount_cents.negative?
        raise WrongDirection, "Une note de crédit se rembourse depuis une ligne SORTANTE."
      elsif !sortante && !@entry.amount_cents.positive?
        raise WrongDirection, "Une facture de vente s'encaisse depuis une ligne ENTRANTE."
      end

      du = @invoice.remaining_cents
      raise AlreadyPaid, "#{@invoice.label} n'attend plus rien." unless du.positive?

      montant = @amount_cents || [du, @entry.remaining_cents.abs].min
      raise TooMuch, "La ligne n'a plus rien à imputer." unless montant.positive?
      if montant > du
        raise TooMuch, "#{@invoice.label} n'attend que #{Money.new(du, 'EUR').format} — " \
                       "en imputer #{Money.new(montant, 'EUR').format} la surpaierait."
      end
      if montant > @entry.remaining_cents.abs
        raise TooMuch, "La ligne ne porte plus que #{Money.new(@entry.remaining_cents.abs, 'EUR').format}."
      end

      PaperTrail.request(whodunnit: @whodunnit || "sales_invoice_payment") do
        ApplicationRecord.transaction do
          @entry.lock!

          @entry.cash_allocations.create!(
            general_account: customer_account,
            legal_entity: @invoice.legal_entity,
            third_party: @invoice.third_party,
            document: @invoice,
            amount_cents: sortante ? -montant : montant,
            label: "#{sortante ? 'Remboursement' : 'Encaissement'} #{@invoice.label}"
          )

          Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: @whodunnit).run! if @entry.reload.fully_allocated?
        end
      end

      @invoice.reload
      @entry.cash_allocations.where(document: @invoice).to_a
    end

    def record_by_ventilation
      raise WrongDirection, "Une facture de vente s'encaisse depuis une ligne ENTRANTE." unless @entry.amount_cents.positive?

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
          # totaliserait un montant que la ligne n'a peut-être plus. Sans
          # montant, ce que la ligne porte encore, jamais la ligne entière.
          base = @amount_cents || @entry.reload.remaining_cents
          if base > @entry.remaining_cents
            raise TooMuch, "La ligne ne porte plus que #{Money.new(@entry.remaining_cents, 'EUR').format}."
          end

          lignes = Finance::VentilateStay.new(stay: stay, amount_cents: base).run!

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

    def customer_account
      @customer_account ||= GeneralAccount.find_by(code: CUSTOMER_CODE) ||
                            raise(MissingAccount, "Le compte clients #{CUSTOMER_CODE} n'existe pas — " \
                                                  "lance `rake accounting:seed_reference`.")
    end
  end
end
