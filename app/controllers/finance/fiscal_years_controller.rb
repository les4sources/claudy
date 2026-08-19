module Finance
  # Les exercices. Leur clôture est ce qui rend une écriture définitivement
  # intouchable — sans elle, « verrouillé » resterait une politesse.
  class FiscalYearsController < Finance::AccountingBaseController
    before_action :get_year, only: [:edit, :update, :destroy, :close]
    breadcrumb "Exercices", :finance_fiscal_years_path, match: :exact

    def index
      @years = FiscalYear.includes(:legal_entity, :journal_entries).ordered
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

    def close
      @year.close!
      redirect_to finance_fiscal_years_path,
                  notice: "Exercice #{@year.label} clôturé — ses écritures ne se corrigent plus que par contre-passation."
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

    def year_params
      params.require(:fiscal_year).permit(:legal_entity_id, :starts_on, :ends_on, :status)
    end
  end
end
