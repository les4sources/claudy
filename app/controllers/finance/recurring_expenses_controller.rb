module Finance
  # Comptabilité > Fournisseurs > Charges fixes (2026-09-30).
  #
  # Ce que la maison paie à intervalle régulier — Voo, une assurance, un
  # emprunt — écrit une fois pour que la trésorerie le projette. Une charge se
  # crée ici directement (un prélèvement sans facture encodée) ou depuis une
  # facture d'achat (« Cette charge revient »), qui préremplit le formulaire.
  class RecurringExpensesController < Finance::AccountingBaseController
    before_action :get_recurring_expense, only: %i[edit update destroy]

    breadcrumb "Charges fixes", :finance_recurring_expenses_path, match: :exact

    def index
      @recurring_expenses = RecurringExpense.ordered.includes(:third_party, :legal_entity).to_a
      @yearly_cents = @recurring_expenses.select(&:active?).sum(&:yearly_cents)
    end

    def new
      @recurring_expense = RecurringExpense.new(
        { legal_entity: default_entity, frequency: "monthly" }.merge(prefill_params.to_h.symbolize_keys)
      )
    end

    def create
      @recurring_expense = RecurringExpense.new(recurring_expense_params)

      if @recurring_expense.save
        redirect_to finance_recurring_expenses_path, notice: "Charge « #{@recurring_expense.label} » créée."
      else
        flash.now[:alert] = @recurring_expense.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @recurring_expense.update(recurring_expense_params)
        redirect_to finance_recurring_expenses_path, notice: "Charge « #{@recurring_expense.label} » mise à jour."
      else
        flash.now[:alert] = @recurring_expense.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    # Une prévision ne porte aucune écriture : la supprimer n'efface aucun fait.
    # Soft delete tout de même, pour que PaperTrail garde la trace.
    def destroy
      @recurring_expense.soft_delete!(validate: false)
      redirect_to finance_recurring_expenses_path, notice: "Charge « #{@recurring_expense.label} » supprimée."
    end

    private

    def get_recurring_expense = @recurring_expense = RecurringExpense.find(params[:id])

    # La Fondation par défaut : c'est la seule entité dont Claudy tient les
    # comptes de trésorerie.
    def default_entity = LegalEntity.actives.find_by(form: "foundation")

    PERMITTED = %i[legal_entity_id third_party_id general_account_id label amount
                   frequency first_due_on ends_on active notes].freeze

    def recurring_expense_params
      params.require(:recurring_expense).permit(*PERMITTED)
    end

    def prefill_params
      params.fetch(:recurring_expense, {}).permit(*PERMITTED)
    end

    def accounting_secondary = "recurring_expenses"
  end
end
