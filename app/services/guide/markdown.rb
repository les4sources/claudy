module Guide
  # Le Markdown du Guide rendu en HTML (CommonMark + tableaux, listes de
  # tâches, liens automatiques, texte barré). Le HTML brut écrit dans une page
  # n'est PAS rendu, et les liens `javascript:` sont neutralisés : la page est
  # lue par tous les comptes, elle ne doit rien pouvoir exécuter.
  #
  # `[[Titre]]` et `[[Titre|texte]]` deviennent des liens vers les pages du
  # Guide (`Guide::Links`) ; un titre qui ne correspond à aucune page reste
  # visible, barré de pointillés — avec `new_page_links`, il ouvre la création
  # de la page (rédacteurs).
  class Markdown
    OPTIONS = {
      parse: { smart: true },
      render: { unsafe: false, hardbreaks: false },
      extension: { strikethrough: true, table: true, autolink: true, tasklist: true, header_ids: "" }
    }.freeze

    # Un titre de la page, pour la table des matières.
    Heading = Struct.new(:level, :text, :anchor, keyword_init: true)

    def self.render(markdown, **) = new(markdown, **)

    # Sans lien résolu : un extrait n'a pas besoin de chercher les pages.
    def self.plain_text(markdown)
      new(markdown, resolve_links: false).document.text.squish
    end

    # `pages` : celles qu'un lien peut viser (le lecteur ne voit pas les pages
    # d'un chapitre qui ne lui est pas ouvert).
    def initialize(markdown, resolve_links: true, new_page_links: false, pages: GuidePage.all)
      @markdown = markdown.to_s.dup.force_encoding(Encoding::UTF_8).scrub
      @resolve_links = resolve_links
      @new_page_links = new_page_links
      @pages = pages
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
        link_pages(fragment)
        fragment
      end
    end

    private

    # Hors code et hors lien déjà posé, chaque `[[…]]` du texte devient un lien.
    def link_pages(fragment)
      fragment.xpath(".//text()[contains(., '[[')][not(ancestor::code) and not(ancestor::pre) and not(ancestor::a)]").each do |text|
        content = text.content
        next unless content.match?(Links::PATTERN)

        html = +""
        last = 0
        content.to_enum(:scan, Links::PATTERN).each do
          match = Regexp.last_match
          html << ERB::Util.h(content[last...match.begin(0)]) << page_link(match[1].strip, match[2]&.strip)
          last = match.end(0)
        end
        html << ERB::Util.h(content[last..])
        text.replace(Nokogiri::HTML5.fragment(html))
      end
    end

    def page_link(title, label)
      text = ERB::Util.h(label.presence || title)
      return text unless @resolve_links

      routes = Rails.application.routes.url_helpers
      if (page = pages_by_key[Links.key(title)])
        %(<a href="#{routes.guide_page_path(page)}" class="guide-wikilink">#{text}</a>)
      elsif @new_page_links
        %(<a href="#{ERB::Util.h(routes.new_guide_page_path(title: title))}" class="guide-wikilink guide-wikilink-missing" ) +
          %(title="Cette page n'existe pas encore : la créer">#{text}</a>)
      else
        %(<span class="guide-wikilink guide-wikilink-missing" title="Cette page n'existe pas encore">#{text}</span>)
      end
    end

    def pages_by_key
      @pages_by_key ||= @pages.select(:id, :title).index_by { |page| Links.key(page.title) }
    end
  end
end
