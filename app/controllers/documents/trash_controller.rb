module Documents
  # La corbeille : restaurer, ou effacer pour de bon (le seul geste sans retour).
  class TrashController < BaseController
    before_action :require_documents_writer!, only: %i[restore destroy]

    def index
      @folders = Documents::Trash.top_folders.includes(:parent).order(deleted_at: :desc).to_a
      @files = Documents::Trash.top_files.includes(:folder, file_attachment: :blob).order(deleted_at: :desc).to_a
      @trash_count = @folders.size + @files.size
    end

    def restore
      folders, files = selected(DocumentFolder.trashed, DocumentFile.trashed)
      moved = Documents::Trash.new(user: current_user).restore(folders: folders, files: files)
      count = folders.size + files.size
      message = "#{plural(count, 'élément')} restauré#{'s' if count > 1}."
      message += " Leur dossier étant à la corbeille, #{moved > 1 ? "#{moved} éléments sont revenus" : 'un élément est revenu'} plus haut." if moved.positive?
      location = count == 1 && files.one? ? documents_file_path(files.first) : documents_trash_path
      respond_done(message, location: location)
    end

    def destroy
      trash = Documents::Trash.new(user: current_user)
      if params[:all].present?
        count = Documents::Trash.count
        trash.empty!
      else
        folders, files = selected(Documents::Trash.top_folders, Documents::Trash.top_files)
        count = folders.size + files.size
        trash.purge(folders: folders, files: files)
      end
      respond_done("#{plural(count, 'élément')} supprimé#{'s' if count > 1} définitivement.", location: documents_trash_path)
    end
  end
end
