module Documents
  # L'arbre des dossiers de la section Documents, chargé en UNE requête : la
  # barre de gauche, le choix « Déplacer vers… » et les chemins des résultats
  # de recherche le lisent tous. Quelques centaines de dossiers au plus : le
  # tenir en mémoire coûte moins qu'une requête par niveau.
  class Tree
    Node = Struct.new(:id, :name, :parent_id, :files_count, keyword_init: true)

    def initialize
      folders = DocumentFolder.kept.pluck(:id, :name, :parent_id)
      counts = DocumentFile.kept.group(:document_folder_id).count
      @nodes = folders.to_h { |id, name, parent_id| [id, Node.new(id: id, name: name, parent_id: parent_id, files_count: counts[id].to_i)] }
      @root_files_count = counts[nil].to_i
      @children = @nodes.values.group_by(&:parent_id).transform_values { |list| list.sort_by { |n| AccentFolding.fold(n.name) } }
    end

    attr_reader :root_files_count

    def empty? = @nodes.empty?

    def node(id) = @nodes[id]

    def children(parent_id) = @children.fetch(parent_id, [])

    def children?(id) = @children.key?(id)

    # Du plus haut au plus proche, le dossier compris.
    def chain(id)
      list = []
      seen = Set.new
      while (current = @nodes[id]) && seen.add?(id)
        list.unshift(current)
        id = current.parent_id
      end
      list
    end

    def path(id) = chain(id).map(&:name).join(" › ")

    # Les dossiers qu'il faut ouvrir pour voir celui-ci dans l'arbre.
    def open_ids(id) = chain(id).map(&:id).to_set

    def subtree_ids(id)
      ids = [id]
      queue = [id]
      while (current = queue.shift)
        children(current).each do |child|
          ids << child.id
          queue << child.id
        end
      end
      ids
    end

    # Tous les dossiers, à plat, dans l'ordre de l'arbre, avec leur chemin :
    # la liste du choix « Déplacer vers… ».
    def flat(parent_id = nil, depth = 0, acc = [])
      children(parent_id).each do |child|
        acc << [child, depth]
        flat(child.id, depth + 1, acc)
      end
      acc
    end
  end
end
