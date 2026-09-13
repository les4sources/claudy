module ExpenseReports
  # « Marquée payée en espèces » (epic #241, phase 1).
  #
  # Le cas courant aux 4 Sources : la trésorière ouvre la caisse et rend ses
  # 87,40 € à Sébastien. Ça ne se note pas « payée » à la main — ça crée une
  # vraie sortie de caisse, affectée sur le 440000 avec la note en document.
  # Sans quoi la dette resterait au grand livre alors que l'argent est parti,
  # et la caisse serait fausse de la même somme.
  #
  # Le virement bancaire, lui, se rapproche depuis « À affecter » (phase 3) et
  # posera exactement le même statut : il n'y aura rien à défaire ici.
  class PayInCash < ServiceBase
    class BadStatus < StandardError; end
    class NoCashAccount < StandardError; end
    class MonthClosed < StandardError; end

    SUPPLIER_CODE = "440000".freeze

    def initialize(expense_report:, paid_on: nil, cash_account: nil, whodunnit: nil)
      @report = expense_report
      @paid_on = paid_on.presence
      @cash_account = cash_account
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { expense_report: @report.id }) { pay }
    end

    def run! = pay

    private

    def pay
      unless @report.processing?
        raise BadStatus,
              "Seule une note en traitement se paie — celle-ci est #{@report.status_label.downcase}."
      end

      account = @cash_account || default_cash_account
      if account.blank?
        raise NoCashAccount,
              "Aucune caisse active pour #{@report.legal_entity.name} — " \
              "crée-la dans Comptabilité > Vue d'ensemble avant de payer en espèces."
      end

      date = parsed_date
      if MonthClosing.closed?(date)
        raise MonthClosed,
              "#{I18n.l(date.beginning_of_month, format: '%B %Y')} est arrêté — " \
              "une sortie de caisse ne s'y ajoute plus."
      end

      amount = -@report.total_cents

      PaperTrail.request(whodunnit: @whodunnit || "expense_reports") do
        ApplicationRecord.transaction do
          entry = CashEntry.create!(
            cash_account: account, entry_date: date, amount_cents: amount,
            label: "#{@report.kind_label} #{@report.reference} — #{@report.human&.name}"
          )
          entry.cash_allocations.create!(
            general_account: supplier_account,
            legal_entity: @report.legal_entity,
            third_party: ThirdParty.for_human!(@report.human),
            document: @report,
            amount_cents: amount,
            label: entry.label
          )
          Accounting::PostCashEntry.new(cash_entry: entry, whodunnit: @whodunnit).run!

          @report.update!(status: "paid", paid_on: date)
          entry
        end
      end

      @report.reload
    end

    def default_cash_account
      CashAccount.actives.where(kind: "cash", legal_entity_id: @report.legal_entity_id).ordered.first
    end

    def supplier_account
      GeneralAccount.find_by(code: SUPPLIER_CODE) ||
        raise(Accounting::PostExpenseReport::MissingAccount,
              "Le compte #{SUPPLIER_CODE} n'existe pas — lance `rake accounting:seed_reference`.")
    end

    def parsed_date
      return Date.current if @paid_on.blank?

      @paid_on.is_a?(String) ? Date.parse(@paid_on) : @paid_on
    end
  end
end
