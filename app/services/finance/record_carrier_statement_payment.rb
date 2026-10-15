module Finance
  # Le virement qui paie un relevé de porteur d'activité (epic #244, phase 3).
  #
  # Le relevé émis entrait dans « À payer » et sa page promettait qu'il « se
  # solde par rapprochement » — mais aucun geste ne permettait ce
  # rapprochement : il y restait pour toujours, prêt à être payé deux fois
  # (relevé de Manon, octobre 2026, déjà réglé par deux de ses factures).
  #
  # Affecter la ligne bancaire sortante sur les dettes fournisseurs (`440000`)
  # avec le RELEVÉ en `document` et le tiers payé (le porteur, ou le tiers qui
  # le paie) sur l'allocation : c'est le tiers de l'écriture du relevé, la
  # dette se lettre. Le `after_commit` de `CashAllocation` fait passer le relevé
  # `paid` quand il est couvert. Plusieurs virements peuvent solder un relevé —
  # un porteur qui facture chaque atelier à part est payé en plusieurs fois.
  #
  # Jumeau de `Finance::RecordExpenseReportPayment`.
  class RecordCarrierStatementPayment < ServiceBase
    class NotPayable < StandardError; end
    class WrongDirection < StandardError; end
    class TooMuch < StandardError; end
    class MissingAccount < StandardError; end

    SUPPLIER_CODE = "440000".freeze

    def initialize(carrier_statement:, cash_entry:, amount_cents: nil, whodunnit: nil)
      @statement = carrier_statement
      @entry = cash_entry
      @amount_cents = amount_cents&.to_i&.abs
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { carrier_statement: @statement&.id }) { record }
    def run! = record

    private

    def record
      raise NotPayable, "Aucun relevé à payer." if @statement.blank?
      raise NotPayable, "Un brouillon ne se paie pas : émets d'abord le relevé." if @statement.draft?
      raise WrongDirection, "Un relevé se paie depuis une ligne SORTANTE." unless @entry.amount_cents.negative?

      du = @statement.remaining_cents
      raise NotPayable, "Ce relevé est déjà entièrement rapproché." unless du.positive?

      # Sans montant explicite on solde ce qui reste, dans la limite de ce que la
      # ligne peut encore porter.
      montant = @amount_cents || [du, @entry.remaining_cents.abs].min
      if montant > du
        raise TooMuch,
              "Ce relevé n'attend que #{Money.new(du, 'EUR').format} — " \
              "en affecter #{Money.new(montant, 'EUR').format} le surpaierait."
      end

      PaperTrail.request(whodunnit: @whodunnit || "carrier_statement_payment") do
        ApplicationRecord.transaction do
          @entry.lock!

          @entry.cash_allocations.create!(
            general_account: supplier_account,
            legal_entity: legal_entity,
            third_party: @statement.payable_third_party,
            document: @statement,
            amount_cents: -montant,
            label: "Paiement #{@statement.payable_label} — #{@statement.reference}"
          )

          Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: @whodunnit).run! if @entry.reload.fully_allocated?
        end
      end

      @statement.reload
    end

    # L'entité qui porte la dette : celle de l'écriture du relevé, à défaut
    # celle du compte de trésorerie.
    def legal_entity
      JournalEntry.find_by(source: @statement, journal: "purchases")&.legal_entity || @entry.cash_account.legal_entity
    end

    def supplier_account
      @supplier_account ||= GeneralAccount.find_by(code: SUPPLIER_CODE) ||
                            raise(MissingAccount,
                                  "Le compte des dettes fournisseurs #{SUPPLIER_CODE} n'existe pas — " \
                                  "lance `rake accounting:seed_reference`.")
    end
  end
end
