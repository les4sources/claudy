module Guide
  # Le Markdown du Guide rendu en HTML (CommonMark + tableaux, listes de
  # tâches, liens automatiques, texte barré). Le HTML brut écrit dans une page
  # n'est PAS rendu, et les liens `javascript:` sont neutralisés : la page est
  # lue par tous les comptes, elle ne doit rien pouvoir exécuter.
  class Markdown
    OPTIONS = {
      parse: { smart: true },
      render: { unsafe: false, hardbreaks: false },
      extension: { strikethrough: true, table: true, autolink: true, tasklist: true, header_ids: "" }
    }.freeze

    # Un titre de la page, pour la table des matières.
    Heading = Struct.new(:level, :text, :anchor, keyword_init: true)

    def self.render(markdown) = new(markdown)

    def self.plain_text(markdown)
      new(markdown).document.text.squish
    end

    def initialize(markdown)
      @markdown = markdown.to_s.dup.force_encoding(Encoding::UTF_8).scrub
    end

    def to_html
      document.to_html.html_safe # rubocop:disable Rails/OutputSafety -- HTML brut refusé par CommonMark (`unsafe: false`)
    end

    # Les titres de niveau 2 et 3, dans l'ordre : la table des matières.
    def headings
      document.css("h2, h3").filter_map do |node|
        anchor = node["id"].presence || node.at_css("a.anchor")&.[]("id")
        next if anchor.blank?

        Heading.new(level: node.name[1].to_i, text: node.text.strip, anchor: anchor)
      end
    end

    def document
      @document ||= begin
        html = Commonmarker.to_html(@markdown, options: OPTIONS, plugins: { syntax_highlighter: nil })
        fragment = Nokogiri::HTML5.fragment(html)
        # Un saut d'ancre laissé à Turbo 7 recharge la page au second clic
        # (même ancre déjà dans l'URL) : le navigateur s'en charge seul.
        fragment.css("a.anchor").each do |anchor|
          anchor["href"] = "##{anchor.parent['id'].presence || anchor['id']}"
          anchor["data-turbo"] = "false"
          anchor["aria-label"] = "Lien vers « #{anchor.parent.text.strip} »"
        end
        fragment.css("a[href]").each do |link|
          next unless link["href"].to_s.match?(%r{\Ahttps?://}i)

          link["target"] = "_blank"
          link["rel"] = "noopener noreferrer"
        end
        fragment.css("img").each { |image| image["loading"] = "lazy" }
        fragment
      end
    end
  end
end
