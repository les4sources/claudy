module Documents
  # Les gestes sur une sélection (un élément ou plusieurs, cochés ou glissés) :
  # ranger ailleurs, jeter à la corbeille.
  class ItemsController < BaseController
    def move
      target = target_folder(params[:target_folder_id])
      folders, files = selected(DocumentFolder.kept, DocumentFile.kept)
      count = Documents::Move.new(target: target).call(folders: folders, files: files)
      where = target ? "« #{target.name} »" : "Documents"
      message = count.zero? ? "Rien à déplacer : c’est déjà dans #{where}." : "#{plural(count, 'élément')} déplacé#{'s' if count > 1} dans #{where}."
      respond_done(message, location: back_location(folder_location(target)))
    rescue Documents::Move::Refused => e
      respond_refused(e.message, location: back_location)
    rescue ActiveRecord::RecordNotFound
      respond_refused("Ce dossier n’existe plus.", location: back_location)
    end

    def trash
      folders, files = selected(DocumentFolder.kept, DocumentFile.kept)
      count = Documents::Trash.new(user: current_user).put(folders: folders, files: files)
      label = folders.empty? && files.one? ? "« #{files.first.name} »" : plural(count, "élément")
      location = back_location
      # Jeter le fichier ou le dossier qu'on regarde : retour au dossier parent.
      location = folder_location(files.first.folder) if files.one? && location.include?(documents_file_path(files.first))
      location = folder_location(folders.first.parent) if folders.one? && location.include?(documents_folder_path(folders.first))
      respond_done("#{label} mis à la corbeille.", location: location)
    end
  end
end
