module Documents
  # Ranger des dossiers et des fichiers dans un autre dossier (ou à la racine,
  # `target` nil), par glisser-déposer ou par « Déplacer vers… ». Tout ou rien :
  # un seul élément refusé (un dossier dans lui-même, un nom déjà pris…) et rien
  # ne bouge, avec la raison.
  class Move
    Refused = Class.new(StandardError)

    def initialize(target:)
      @target = target
    end

    def call(folders: [], files: [])
      raise Refused, "Ce dossier est à la corbeille." if @target&.trashed?

      target_id = @target&.id
      moved = 0
      ApplicationRecord.transaction do
        Array(folders).each do |folder|
          next if folder.parent_id == target_id

          folder.parent_id = target_id
          save!(folder)
          moved += 1
        end
        Array(files).each do |file|
          next if file.document_folder_id == target_id

          file.document_folder_id = target_id
          save!(file)
          moved += 1
        end
      end
      moved
    end

    private

    def save!(item)
      return if item.save

      raise Refused, "#{item.name} : #{item.errors.full_messages.to_sentence}"
    end
  end
end
