module Finance
  # Comptabilité › États › Export comptable (revue expert-comptable du
  # 2026-10-20) : un exercice d'une entité, en un ZIP de CSV pour le comptable.
  class AccountantExportsController < Finance::AccountingBaseController
    breadcrumb "Export comptable", :finance_accountant_export_path, match: :exact

    def show
      @years = FiscalYear.includes(:legal_entity).sort_by { |year| [year.legal_entity.form == "foundation" ? 0 : 1, year.legal_entity.name, -year.starts_on.jd] }
      @year = FiscalYear.find_by(id: params[:fiscal_year_id]) || @years.find { |year| year.covers?(Date.current) } || @years.first
    end

    def download
      year = FiscalYear.find(params.require(:fiscal_year_id))
      export = Accounting::AccountantExport.new(year)
      send_data export.zip, type: "application/zip", filename: export.filename
    end
  end
end
