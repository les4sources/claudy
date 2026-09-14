module Finance
  # Comptabilité > Notes de frais (epic #241, phase 1).
  #
  # La compta encode depuis le papier (décision de Michael du 2026-09-07) : la
  # saisie par la personne elle-même viendra plus tard. L'écran est donc conçu
  # pour ÇA — une feuille à plusieurs lignes qu'on recopie d'une traite, les
  # photos des tickets déposées au passage, puis deux clics pour la passer en
  # traitement.
  #
  # L'action de passage en traitement ne s'appelle pas `process` : c'est déjà le
  # point d'entrée de toute action Rails (`AbstractController#process`), et
  # l'écraser casserait le contrôleur entier.
  class ExpenseReportsController < Finance::AccountingBaseController
    before_action :get_report, only: %i[show edit update destroy start_processing reject pay_in_cash unprocess]

    breadcrumb "Notes de frais", :finance_expense_reports_path, match: :exact

    def index
      @reports = filtered_scope.includes(:human, :legal_entity, :expense_lines).recent_first
      @totals = totals_for(@reports)
      @humans = Human.ordered_all
      @entities = LegalEntity.actives.ordered
    end

    def show
      breadcrumb @report.reference.presence || "Note ##{@report.id}",
                 finance_expense_report_path(@report), match: :exact
      @lines = @report.expense_lines.chronological.includes(:general_account, :team)
      @entry = @report.journal_entry
    end

    def new
      @report = ExpenseReport.new(
        kind: params[:kind].presence_in(ExpenseReport::KINDS) || "expenses",
        legal_entity: default_entity,
        submitted_on: Date.current
      )
      @report.expense_lines.build(spent_on: Date.current)
      load_form_collections
    end

    def create
      @report = ExpenseReport.new(report_params)
      @report.created_by = current_user

      if @report.save
        redirect_to finance_expense_report_path(@report),
                    notice: "Note enregistrée — #{@report.expense_lines.size} ligne(s), #{helpers.expense_amount(@report.total_cents)}."
      else
        load_form_collections
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      return refuse_edit unless @report.editable?

      @report.expense_lines.build(spent_on: Date.current) if @report.expense_lines.empty?
      load_form_collections
    end

    def update
      return refuse_edit unless @report.editable?

      if @report.update(report_params)
        redirect_to finance_expense_report_path(@report), notice: "Note mise à jour."
      else
        load_form_collections
        render :edit, status: :unprocessable_entity
      end
    end

    # Une note enregistrée ou rejetée se supprime — rien ne la référence encore.
    # Passée en traitement, elle porte une pièce comptable : elle se contre-passe.
    def destroy
      if @report.editable? || @report.rejected?
        @report.soft_delete!
        redirect_to finance_expense_reports_path, notice: "Note supprimée."
      else
        redirect_to finance_expense_report_path(@report),
                    alert: "Une note en traitement ne se supprime pas — contre-passe son écriture."
      end
    end

    def start_processing
      ExpenseReports::Process.new(expense_report: @report, processed_on: params[:processed_on],
                                  whodunnit: current_user&.email).run!
      redirect_to finance_expense_report_path(@report),
                  notice: "Note #{@report.reload.reference} passée en traitement — l'écriture est au grand livre."
    rescue ExpenseReports::Process::BadStatus, ExpenseReports::Process::NoLines,
           ExpenseReports::Process::MissingFiscalYear,
           Accounting::PostExpenseReport::MissingAccount,
           Accounting::PostExpenseReport::NoLines,
           Accounting::PostDocument::MissingFiscalYear, Date::Error => e
      redirect_to finance_expense_report_path(@report), alert: e.message
    end

    def reject
      ExpenseReports::Reject.new(expense_report: @report, reason: params[:rejection_reason],
                                 whodunnit: current_user&.email).run!
      redirect_to finance_expense_report_path(@report), notice: "Note rejetée, avec son motif."
    rescue ExpenseReports::Reject::BadStatus, ExpenseReports::Reject::MissingReason,
           ActiveRecord::RecordInvalid => e
      redirect_to finance_expense_report_path(@report), alert: e.message
    end

    def pay_in_cash
      ExpenseReports::PayInCash.new(expense_report: @report, paid_on: params[:paid_on],
                                    whodunnit: current_user&.email).run!
      redirect_to finance_expense_report_path(@report),
                  notice: "Note payée en espèces — la sortie de caisse est enregistrée."
    rescue ExpenseReports::PayInCash::BadStatus, ExpenseReports::PayInCash::NoCashAccount,
           ExpenseReports::PayInCash::MonthClosed,
           Accounting::PostExpenseReport::MissingAccount,
           Accounting::PostCashEntry::NotFullyAllocated,
           Accounting::PostDocument::MissingFiscalYear,
           ActiveRecord::RecordInvalid, Date::Error => e
      redirect_to finance_expense_report_path(@report), alert: e.message
    end

    def unprocess
      ExpenseReports::Unprocess.new(expense_report: @report, whodunnit: current_user&.email).run!
      redirect_to finance_expense_report_path(@report),
                  notice: "Écriture contre-passée — la note est de nouveau modifiable, elle garde son numéro."
    rescue ExpenseReports::Unprocess::NotProcessing, ExpenseReports::Unprocess::AlreadyPaid,
           ExpenseReports::Unprocess::ClosedFiscalYear,
           Accounting::ReverseEntry::AlreadyReversed,
           Accounting::PostDocument::MissingFiscalYear => e
      redirect_to finance_expense_report_path(@report), alert: e.message
    end

    private

    def get_report = @report = ExpenseReport.includes(:expense_lines).find(params[:id])

    def refuse_edit
      redirect_to finance_expense_report_path(@report),
                  alert: "Cette note n'est plus modifiable — sa pièce comptable existe."
    end

    def filtered_scope
      scope = ExpenseReport.all
      scope = scope.with_status(params[:status]) if params[:status].presence_in(ExpenseReport::STATUSES)
      scope = scope.of_kind(params[:kind]) if params[:kind].presence_in(ExpenseReport::KINDS)
      scope = scope.for_human(params[:human_id]) if params[:human_id].present?
      scope = scope.where(legal_entity_id: params[:legal_entity_id]) if params[:legal_entity_id].present?
      scope = scope.where(submitted_on: ..parsed_date(params[:to])) if parsed_date(params[:to])
      scope = scope.where(submitted_on: parsed_date(params[:from])..) if parsed_date(params[:from])
      scope
    end

    # Les totaux se lisent en une requête sur les lignes plutôt qu'en chargeant
    # chaque note : une liste filtrée sur un trimestre en compte vite cent.
    def totals_for(scope)
      by_report = ExpenseLine.where(expense_report_id: scope.reload.map(&:id))
                             .group(:expense_report_id).sum(:amount_cents)
      {
        count: by_report.size,
        total_cents: by_report.values.sum,
        to_pay_cents: scope.select(&:processing?).sum { |r| by_report[r.id].to_i }
      }
    end

    def load_form_collections
      @humans = Human.ordered_all
      @entities = LegalEntity.actives.ordered
      # Les charges (classe 6) d'abord, les immobilisations (classe 2) ensuite :
      # une note de frais paie surtout des achats, mais parfois un outil qui
      # s'immobilise. Le reste du plan n'a rien à faire dans une note.
      @accounts = GeneralAccount.actives.where(klass: [6, 2]).ordered
      @teams = Team.ordered
    end

    def default_entity
      LegalEntity.find_by(name: "Fondation Les 4 Sources") || LegalEntity.actives.ordered.first
    end

    def parsed_date(raw)
      raw.present? ? Date.parse(raw) : nil
    rescue Date::Error
      nil
    end

    def report_params
      params.require(:expense_report).permit(
        :kind, :human_id, :legal_entity_id, :submitted_on, :notes,
        expense_lines_attributes: %i[id spent_on label supplier_name doc_kind amount_in_euros
                                     general_account_id team_id analytic_account_id
                                     distance_km position receipt _destroy]
      )
    end

    def accounting_secondary = "expense_reports"
  end
end
