module Documents
  # Parcourir les documents : la racine (`index`) ou un dossier (`show`), avec
  # la recherche par nom (`q`) dans tous les dossiers.
  class FoldersController < BaseController
    before_action :require_documents_writer!, only: %i[create update]

    def index
      @folder = nil
      load_listing
      render :show
    end

    def show
      @folder = DocumentFolder.find(params[:id].to_i)
      return redirect_to(documents_trash_path, alert: "Ce dossier est à la corbeille.") if @folder.trashed?

      load_listing
    end

    def create
      parent = target_folder(params.dig(:folder, :parent_id))
      name = params.dig(:folder, :name).to_s.squish.presence || "Nouveau dossier"
      folder = DocumentFolder.new(parent: parent, created_by: current_user,
                                  name: DocumentFolder.available_name(name, parent&.id))
      if folder.save
        redirect_to folder_location(parent), notice: ERB::Util.html_escape("Dossier « #{folder.name} » créé."), status: :see_other
      else
        redirect_to folder_location(parent), alert: ERB::Util.html_escape(folder.errors.full_messages.to_sentence), status: :see_other
      end
    end

    # Renommer.
    def update
      folder = DocumentFolder.kept.find(params[:id].to_i)
      old = folder.name
      if folder.update(name: params.dig(:folder, :name))
        respond_done(old == folder.name ? "Le nom n’a pas changé." : "« #{old} » s’appelle maintenant « #{folder.name} ».", location: back_location(folder_location(folder.parent)))
      else
        respond_refused(folder.errors.full_messages.to_sentence, location: back_location)
      end
    end

    private

    def load_listing
      @query = params[:q].to_s.squish.first(80)
      @sort = %w[name recent size].include?(params[:tri]) ? params[:tri] : "name"
      @listing = Documents::Listing.new(folder: @folder, query: @query, sort: @sort)
      @ancestors = @folder ? @folder.ancestors : []
      @trash_count = Documents::Trash.count
    end
  end
end
