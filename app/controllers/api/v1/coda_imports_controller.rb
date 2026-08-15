module Api
  module V1
    # Dépôt d'un fichier CODA par l'API (#198).
    #
    # Passe par `Coda::Import`, le MÊME service que l'écran, et rend son rapport
    # tel quel — statut, relevés, lignes créées, messages. L'import est
    # synchrone, comme à l'écran et pour la même raison : un import bancaire qui
    # échoue en silence dans un job est une panne qu'on découvre trois mois plus
    # tard, à la clôture.
    #
    # Un fichier déjà déposé rend **200**, pas une erreur : rejouer un import est
    # une opération normale, et c'est ce qui rend une reprise en plusieurs passes
    # possible. Un fichier refusé rend 422 avec le motif chiffré du service — il
    # porte le relevé et l'écart, c'est ce dont la compta a besoin pour savoir
    # quoi demander à la banque.
    class CodaImportsController < BaseController
      def index
        @coda_imports = paginate(CodaImport.ordered.includes(:coda_statements))
      end

      def show
        @coda_import = CodaImport.includes(coda_statements: :cash_account).find(params[:id])
      end

      def create
        content = params.require(:content).to_s
        if content.blank?
          return render json: { error: "unprocessable_entity", message: "Contenu du fichier vide." },
                        status: :unprocessable_entity
        end

        @report = Coda::Import.new(content: content,
                                   filename: params[:filename].presence || "depot-api.coda",
                                   whodunnit: "api:agent").run!
        @coda_import = @report.coda_import

        render :show, status: @report.status == "imported" ? :created : :ok
      rescue Coda::Import::Rejected, Coda::ParseError => e
        render json: { error: "unprocessable_entity", message: e.message }, status: :unprocessable_entity
      end
    end
  end
end
