module Finance
  # Le virement qui paie une note de frais ou de mission (epic #241, phase 3).
  #
  # Affecter la ligne bancaire sortante sur les dettes fournisseurs (`440000`)
  # avec la NOTE en `document` et le tiers du bénéficiaire sur l'allocation.
  # C'est ce lien qui fait passer la note en `paid` — via
  # `ExpenseReports::RefreshPayment`, déclenché par le `after_commit` de
  # `CashAllocation`, qui déclenche à son tour l'email au bénéficiaire. Rien
  # n'est coché ici : le paiement est un rapprochement (décision 6).
  #
  # Jumeau de `Finance::RecordInvoicePayment`. Le paiement en espèces
  # (`ExpenseReports::PayInCash`) pose exactement le même état par le même
  # chemin : il n'y a qu'une façon d'être payée.
  class RecordExpenseReportPayment < ServiceBase
    class NotPayable < StandardError; end
    class WrongDirection < StandardError; end
    class TooMuch < StandardError; end
    class MissingAccount < StandardError; end

    SUPPLIER_CODE = "440000".freeze

    def initialize(expense_report:, cash_entry:, amount_cents: nil, whodunnit: nil)
      @report = expense_report
      @entry = cash_entry
      @amount_cents = amount_cents&.to_i&.abs
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { expense_report: @report&.id }) { record }
    def run! = record

    private

    def record
      raise NotPayable, "Aucune note à payer." if @report.blank?
      unless @report.processing?
        raise NotPayable,
              "Seule une note en traitement se rapproche — celle-ci est #{@report.status_label.downcase}."
      end
      raise WrongDirection, "Une note se paie depuis une ligne SORTANTE." unless @entry.amount_cents.negative?

      du = @report.remaining_cents
      raise NotPayable, "Cette note est déjà entièrement rapprochée." unless du.positive?

      # Sans montant explicite on solde ce qui reste, dans la limite de ce que la
      # ligne peut encore porter : un virement groupé paie plusieurs notes.
      montant = @amount_cents || [du, @entry.remaining_cents.abs].min
      if montant > du
        raise TooMuch,
              "Cette note n'attend que #{Money.new(du, 'EUR').format} — " \
              "en affecter #{Money.new(montant, 'EUR').format} la surpaierait."
      end

      PaperTrail.request(whodunnit: @whodunnit || "expense_report_payment") do
        ApplicationRecord.transaction do
          @entry.lock!

          @entry.cash_allocations.create!(
            general_account: supplier_account,
            legal_entity: @report.legal_entity,
            third_party: ThirdParty.for_human!(@report.human),
            document: @report,
            amount_cents: -montant,
            label: "Paiement #{@report.payable_label} — #{@report.payable_beneficiary}"
          )

          Accounting::PostCashEntry.new(cash_entry: @entry, whodunnit: @whodunnit).run! if @entry.reload.fully_allocated?
        end
      end

      @report.reload
    end

    def supplier_account
      @supplier_account ||= GeneralAccount.find_by(code: SUPPLIER_CODE) ||
                            raise(MissingAccount,
                                  "Le compte des dettes fournisseurs #{SUPPLIER_CODE} n'existe pas — " \
                                  "lance `rake accounting:seed_reference`.")
    end
  end
end
