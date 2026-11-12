# La section Documents (Michael, 2026-11-12) : pictogrammes par type, tailles
# et lignes de détail lisibles.
module DocumentsHelper
  # L'étiquette du type sur le pictogramme : l'extension (« PDF », « XLSX »),
  # sinon le type en clair.
  def document_badge(file)
    ext = file.extension.to_s.upcase
    ext.present? && ext.length <= 4 ? ext : file.kind_label.first(4).upcase
  end

  # Le pictogramme d'un fichier : une feuille à coin plié teintée par type, ou
  # la vignette pour une photo.
  def document_icon(file, size: :m)
    if file.thumbnail? && size != :s
      return content_tag(:span, class: "ui-doc-ic ui-doc-ic-#{size} ui-doc-ic-thumb") do
        image_tag(thumb_documents_file_path(file), alt: "", loading: "lazy", decoding: "async")
      end
    end

    content_tag(:span, class: "ui-doc-ic ui-doc-ic-#{size} ui-doc-k-#{file.kind}", "aria-hidden": "true") do
      content_tag(:svg, '<path d="M6 2h8l6 6v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2Z"/><path d="M14 2v6h6"/>'.html_safe,
                  viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": 1.5, "stroke-linejoin": "round") +
        content_tag(:b, document_badge(file))
    end
  end

  def document_folder_icon(size: 22)
    content_tag(:span, class: "ui-doc-fic", "aria-hidden": "true") do
      content_tag(:svg, '<path d="M3 6.5A2.5 2.5 0 0 1 5.5 4h3.6a2 2 0 0 1 1.6.8l1 1.4a2 2 0 0 0 1.6.8h5.2A2.5 2.5 0 0 1 21 9.5v8a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z"/>'.html_safe,
                  width: size, height: size, viewBox: "0 0 24 24", fill: "currentColor")
    end
  end

  def document_size(bytes)
    number_to_human_size(bytes, precision: 3)
  end

  # « 1 dossier », « 4 dossiers » (le `pluralize` de Rails suit l'anglais).
  def document_count(count, word, plural = "#{word}s") = "#{count} #{count == 1 ? word : plural}"

  # « PDF · 1,2 Mo · Michael, le 12 nov. »
  def document_meta(file)
    who = file.uploaded_by&.linked_human&.name.presence || file.uploaded_by&.email.to_s.split("@").first
    [file.kind_label, document_size(file.byte_size), ["ajouté", (who ? "par #{who}" : nil), document_when(file.created_at)].compact.join(" ")].join(" · ")
  end

  def document_when(time)
    return "" unless time

    date = time.to_date
    if date == Date.current then "aujourd’hui à #{l(time, format: '%H:%M')}"
    elsif date == Date.current - 1 then "hier"
    elsif date.year == Date.current.year then "le #{l(date, format: '%-d %b')}"
    else "le #{l(date, format: '%-d %b %Y')}"
    end
  end

  # Le nom avec les mots cherchés surlignés (sans casse ni accents).
  def document_highlight(name, query)
    words = query.to_s.split.map { |w| AccentFolding.fold(w) }.reject(&:blank?)
    return name if words.empty?

    folded = AccentFolding.fold(name)
    marks = Array.new(name.length, false)
    words.each do |word|
      start = 0
      while (index = folded.index(word, start))
        (index...(index + word.length)).each { |i| marks[i] = true }
        start = index + word.length
      end
    end
    safe_join(name.chars.each_with_index.chunk_while { |(_, a), (_, b)| marks[a] == marks[b] }.map do |chunk|
      text = chunk.map(&:first).join
      marks[chunk.first.last] ? content_tag(:mark, text, class: "ui-doc-mark") : text
    end)
  end

  # Les options du choix « Déplacer vers… » : la racine puis l'arbre, chaque
  # dossier avec la liste de ses ancêtres (`data-path`), pour que le
  # contrôleur retire de la liste un dossier qu'on déplace et ses descendants.
  def document_move_options(tree)
    rows = [{ value: "root", label: "Documents (racine)", path: "" }]
    tree.flat.each do |node, _depth|
      rows << { value: node.id.to_s, label: tree.path(node.id), path: tree.chain(node.id).map(&:id).join("/") }
    end
    rows
  end
end
