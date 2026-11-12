module Documents
  # Envoyer un ou plusieurs fichiers dans un dossier (ou à la racine). Un nom
  # déjà pris est numéroté (« Contrat (2).pdf ») plutôt que refusé : on dépose
  # une pile de PDF sans se soucier de doublons de noms.
  class Upload
    Result = Struct.new(:files, :errors, keyword_init: true)

    def initialize(folder:, user:)
      @folder = folder
      @user = user
    end

    def call(uploads)
      created = []
      errors = []
      Array(uploads).compact_blank.each do |upload|
        next unless upload.respond_to?(:original_filename)

        original = upload.original_filename.to_s.dup.force_encoding(Encoding::UTF_8).scrub.unicode_normalize(:nfc)
        file = DocumentFile.new(folder: @folder, uploaded_by: @user,
                                name: DocumentFile.available_name(clean(original), @folder&.id))
        file.file.attach(upload)
        if file.save
          created << file
        else
          errors << "#{original} : #{file.errors.full_messages.to_sentence}"
        end
      end
      Result.new(files: created, errors: errors)
    end

    private

    def clean(name)
      name.squish.delete("/\\").presence || "Sans nom"
    end
  end
end
