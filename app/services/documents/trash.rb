module Documents
  # La corbeille de la section Documents (cf. `DocumentItem`). Trois gestes :
  #
  # - `put` jette des dossiers et des fichiers. Un dossier emporte tout ce qu'il
  #   contient, marqué du MÊME instant : il se restaurera d'un bloc ;
  # - `restore` les remet où ils étaient. Si leur dossier est lui-même à la
  #   corbeille, ils remontent dans le premier dossier encore en place (ou à la
  #   racine), et un nom déjà repris par un voisin est numéroté ;
  # - `purge` les efface pour de bon, fichiers compris. Seul geste sans retour.
  class Trash
    def initialize(user: nil)
      @user = user
    end

    # Ce qu'on voit dans la corbeille : ce qu'on a jeté, pas chaque fichier
    # d'un dossier jeté.
    def self.top_folders
      DocumentFolder.trashed.joins("LEFT JOIN document_folders parents ON parents.id = document_folders.parent_id")
                    .where("parents.id IS NULL OR parents.deleted_at IS NULL OR parents.deleted_at <> document_folders.deleted_at")
    end

    def self.top_files
      DocumentFile.trashed.joins("LEFT JOIN document_folders folders ON folders.id = document_files.document_folder_id")
                  .where("folders.id IS NULL OR folders.deleted_at IS NULL OR folders.deleted_at <> document_files.deleted_at")
    end

    def self.count = top_folders.count + top_files.count

    def put(folders: [], files: [])
      now = Time.current
      ApplicationRecord.transaction do
        Array(folders).each do |folder|
          next if folder.trashed?

          ids = folder.subtree_ids - [folder.id]
          DocumentFolder.kept.where(id: ids).update_all(deleted_at: now, updated_at: now)
          DocumentFile.kept.where(document_folder_id: ids + [folder.id]).update_all(deleted_at: now, updated_at: now)
          folder.update!(deleted_at: now)
        end
        Array(files).each { |file| file.update!(deleted_at: now) unless file.trashed? }
      end
      Array(folders).size + Array(files).size
    end

    def restore(folders: [], files: [])
      moved = 0
      ApplicationRecord.transaction do
        Array(folders).each do |folder|
          next unless folder.trashed?

          stamp = folder.deleted_at
          ids = folder.subtree_ids - [folder.id]
          parent_id = live_folder_id(folder.parent)
          moved += 1 if parent_id != folder.parent_id
          DocumentFolder.where(id: ids, deleted_at: stamp).update_all(deleted_at: nil, updated_at: Time.current)
          DocumentFile.where(document_folder_id: ids + [folder.id], deleted_at: stamp).update_all(deleted_at: nil, updated_at: Time.current)
          folder.update!(deleted_at: nil, parent_id: parent_id, name: DocumentFolder.available_name(folder.name, parent_id, except: folder.id))
        end
        Array(files).each do |file|
          next unless file.trashed?

          folder_id = live_folder_id(file.folder)
          moved += 1 if folder_id != file.document_folder_id
          file.update!(deleted_at: nil, document_folder_id: folder_id,
                       name: DocumentFile.available_name(file.name, folder_id, except: file.id))
        end
      end
      moved
    end

    def purge(folders: [], files: [])
      ApplicationRecord.transaction do
        folder_ids = DocumentFolder.subtree_ids(Array(folders).map(&:id))
        all_files = DocumentFile.where(id: Array(files).map(&:id)).or(DocumentFile.where(document_folder_id: folder_ids)).to_a
        all_files.each(&:destroy!) # la pièce part avec (`purge_later`)
        # Des feuilles vers la racine : un dossier ne s'efface que vide.
        remaining = DocumentFolder.where(id: folder_ids).to_a
        until remaining.empty?
          leaves = remaining.reject { |folder| remaining.any? { |other| other.parent_id == folder.id } }
          leaves.each(&:destroy!)
          remaining -= leaves
        end
      end
    end

    def empty!
      purge(folders: self.class.top_folders.to_a, files: self.class.top_files.to_a)
    end

    private

    # Le premier dossier encore en place en remontant, sinon la racine (nil).
    def live_folder_id(folder)
      seen = Set.new
      while folder && seen.add?(folder.id)
        return folder.id unless folder.trashed?

        folder = folder.parent
      end
      nil
    end
  end
end
