module Finance
  # Dépôt des fichiers CODA (issue #181).
  #
  # L'import est SYNCHRONE, volontairement : l'ActiveJob de l'app est en
  # adaptateur `async` — un job posé en file disparaît au redémarrage — et un
  # import bancaire qui échoue en silence dans un job est exactement le genre de
  # panne qu'on découvre trois mois plus tard, au moment de la clôture.
  class CodaImportsController < Finance::BaseController
    breadcrumb "Comptabilité", :finance_accounting_path, match: :exact
    breadcrumb "Import CODA", :finance_coda_imports_path, match: :exact

    def index
      @imports = CodaImport.ordered.includes(:coda_statements)
      @accounts = CashAccount.actives.ordered
    end

    def show
      @import = CodaImport.find(params[:id])
      breadcrumb @import.filename, finance_coda_import_path(@import), match: :exact

      @statements = @import.coda_statements.includes(:cash_account).ordered
    end

    def create
      fichier = params[:file]
      if fichier.blank?
        return redirect_to finance_coda_imports_path, alert: "Choisis un fichier CODA à déposer."
      end

      report = Coda::Import.new(content: fichier.read.force_encoding("UTF-8"),
                                filename: fichier.original_filename,
                                whodunnit: current_user&.email).run!

      if report.status == "already_imported"
        redirect_to finance_coda_imports_path, alert: report.to_text
      else
        redirect_to finance_coda_import_path(report.coda_import), notice: report.to_text
      end
    rescue Coda::Import::Rejected, Coda::ParseError => e
      # Le motif est affiché tel quel : il porte le relevé et l'écart chiffré,
      # et c'est ce qui permet à la compta de savoir quoi demander à la banque.
      redirect_to finance_coda_imports_path, alert: e.message
    end

    private

    def finance_secondary = "accounting"
  end
end
