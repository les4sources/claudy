module Documents
  # Ce qu'on voit dans un dossier (ou à la racine) : ses sous-dossiers puis ses
  # fichiers, triés par nom (sans casse ni accents), par date d'envoi ou par
  # taille. Avec une recherche (`query`), la liste porte sur TOUS les dossiers.
  class Listing
    attr_reader :folder, :query, :sort

    def initialize(folder:, query: "", sort: "name")
      @folder = folder
      @query = query.to_s
      @sort = sort
    end

    def searching? = @query.length >= 2

    def folders
      @folders ||= begin
        scope = DocumentFolder.kept
        scope = searching? ? scope.named_like(@query) : scope.where(parent_id: @folder&.id)
        scope = @sort == "recent" ? scope.order(created_at: :desc) : scope.order(Arel.sql(AccentFolding.sql("document_folders.name")))
        scope.to_a
      end
    end

    def files
      @files ||= begin
        scope = DocumentFile.kept.includes(:uploaded_by, file_attachment: :blob)
        scope = searching? ? scope.named_like(@query) : scope.where(document_folder_id: @folder&.id)
        scope = case @sort
                when "recent" then scope.order(created_at: :desc)
                when "size"
                  scope.left_joins(file_attachment: :blob).order(Arel.sql("active_storage_blobs.byte_size DESC NULLS LAST"))
                else scope.order(Arel.sql(AccentFolding.sql("document_files.name")))
                end
        scope.to_a
      end
    end

    def empty? = folders.empty? && files.empty?

    def total_bytes = files.sum(&:byte_size)

    # Ce que contient chaque sous-dossier affiché : « 3 dossiers · 12 fichiers ».
    def contents(tree, folder_id)
      subfolders = tree.children(folder_id).size
      files_count = tree.node(folder_id)&.files_count.to_i
      [(subfolders.positive? ? "#{subfolders} dossier#{'s' if subfolders > 1}" : nil),
       (files_count.positive? ? "#{files_count} fichier#{'s' if files_count > 1}" : nil)].compact.join(" · ").presence || "Vide"
    end
  end
end
