module Finance
  # Comptabilité › États › Comptes annuels (revue expert-comptable du
  # 2026-10-20) : le bilan, le compte de résultats et l'affectation d'un
  # exercice au schéma abrégé de la BNB, en regard de l'exercice précédent.
  class AnnualAccountsController < Finance::AccountingBaseController
    breadcrumb "Comptes annuels", :finance_annual_accounts_path, match: :exact

    def show
      @years = FiscalYear.includes(:legal_entity).sort_by { |year| [year.legal_entity.form == "foundation" ? 0 : 1, year.legal_entity.name, -year.starts_on.jd] }
      @year = params[:fiscal_year_id].present? ? FiscalYear.find(params[:fiscal_year_id]) : default_year
      @accounts = @year && Accounting::AnnualAccounts.new(@year)
      @detail = params[:detail] == "1"

      respond_to do |format|
        format.html
        format.csv do
          raise ActiveRecord::RecordNotFound if @accounts.nil?

          send_data Accounting::AccountantExport.statements_csv(@accounts), type: "text/csv; charset=utf-8",
                                                                             filename: "comptes-annuels-#{@year.label}-#{@year.legal_entity.name.parameterize}.csv"
        end
      end
    end

    private

    # L'exercice en cours de la fondation : celui qu'on regarde le plus.
    def default_year
      foundation = LegalEntity.actives.find_by(form: "foundation") || LegalEntity.actives.ordered.first
      foundation&.fiscal_year_for(Date.current) || foundation&.fiscal_years&.max_by(&:starts_on)
    end
  end
end
