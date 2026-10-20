module Finance
  # Les exercices. Leur clôture est ce qui rend une écriture définitivement
  # intouchable — sans elle, « verrouillé » resterait une politesse.
  class FiscalYearsController < Finance::AccountingBaseController
    before_action :get_year, only: [:edit, :update, :destroy, :closing, :close, :reopen]
    breadcrumb "Exercices", :finance_fiscal_years_path, match: :exact

    def index
      # Le refus de supprimer une entité pointe ici avec `legal_entity_id` : on
      # arrive devant ses exercices à elle, pas devant la liste entière à
      # chercher lesquels la concernent.
      @entity_filter = LegalEntity.find_by(id: params[:legal_entity_id])
      @years = FiscalYear.includes(:legal_entity, :journal_entries).ordered
      @years = @years.where(legal_entity_id: @entity_filter.id) if @entity_filter
      # Le seul exercice que chaque entité peut rouvrir : son dernier clôturé.
      @reopenable_ids = FiscalYear.where(status: "closed").group(:legal_entity_id).maximum(:starts_on)
                                  .filter_map { |entity_id, starts_on| FiscalYear.find_by(legal_entity_id: entity_id, starts_on: starts_on)&.id }
    end

    def new
      year = Date.current.year
      @year = FiscalYear.new(starts_on: Date.new(year, 1, 1), ends_on: Date.new(year, 12, 31))
    end

    def create
      @year = FiscalYear.new(year_params)

      if @year.save
        redirect_to finance_fiscal_years_path, notice: "Exercice #{@year.label} créé."
      else
        flash.now[:alert] = @year.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @year.update(year_params)
        redirect_to finance_fiscal_years_path, notice: "Exercice mis à jour."
      else
        flash.now[:alert] = @year.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    # L'aperçu de la clôture : le résultat et son affectation, l'à-nouveau qui
    # sera posé, ce qui bloque et ce qui mérite un regard. Rien n'est écrit.
    def closing
      breadcrumb "Clôturer #{@year.label}", closing_finance_fiscal_year_path(@year)
      @closing = Accounting::CloseFiscalYear.new(fiscal_year: @year, opening: params[:opening])
      @preview = @closing.preview
    end

    def close
      closing = Accounting::CloseFiscalYear.new(fiscal_year: @year, opening: params[:opening], whodunnit: current_user&.email)
      closing.run!
      redirect_to finance_fiscal_years_path,
                  notice: "Exercice #{@year.label} de #{@year.legal_entity.name} clôturé : résultat affecté, écritures " \
                          "verrouillées#{closing.opening == 'none' ? '' : ', à-nouveau posé'}."
    rescue ServiceError, ActiveRecord::RecordInvalid => e
      redirect_to closing_finance_fiscal_year_path(@year, opening: params[:opening]), alert: e.message
    end

    # Rouvrir : le dernier exercice clôturé d'une entité seulement, et avec un
    # motif. L'affectation et l'à-nouveau de la clôture se contre-passent.
    def reopen
      Accounting::ReopenFiscalYear.new(fiscal_year: @year, reason: params[:reason], whodunnit: current_user&.email).run!
      redirect_to finance_fiscal_years_path, notice: "Exercice #{@year.label} rouvert : affectation et à-nouveau contre-passés."
    rescue ServiceError, ActiveRecord::RecordInvalid => e
      redirect_to finance_fiscal_years_path, alert: e.message
    end

    def destroy
      if @year.destroy
        redirect_to finance_fiscal_years_path, notice: "Exercice supprimé."
      else
        redirect_to finance_fiscal_years_path, alert: "Cet exercice porte des écritures."
      end
    end

    private

    def get_year = @year = FiscalYear.find(params[:id])

    # Pas de `status` : un exercice se clôture par sa clôture (affectation,
    # verrouillage, à-nouveau) et se rouvre par `reopen`, motif à l'appui —
    # jamais par un champ de formulaire (revue du 2026-10-20).
    def year_params
      params.require(:fiscal_year).permit(:legal_entity_id, :starts_on, :ends_on)
    end
  end
end
