module Guide
  # Les liens entre pages du Guide (Michael, 2026-10-19) : `[[Titre]]` ou
  # `[[Titre|texte affiché]]` dans le Markdown. Une page est retrouvée par son
  # titre, sans tenir compte des majuscules ni des accents ; renommer une page
  # réécrit les liens qui la visent (`Guide::SavePage`).
  module Links
    PATTERN = /\[\[([^\[\]|\n]+?)(?:\|([^\[\]\n]+?))?\]\]/

    module_function

    # « Note de Frais » et « note de frais » désignent la même page — et
    # « d’un » (typographie du rendu) « d'un ».
    def key(title)
      title.to_s.tr("’‘“”", %(''"")).unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.squish
    end

    # Les titres visés par un Markdown, normalisés.
    def targets(markdown)
      markdown.to_s.scan(PATTERN).map { |title, _label| key(title) }.uniq
    end

    # Le Markdown où les liens vers `old_title` visent désormais `new_title`
    # (le texte affiché choisi, s'il y en a un, est gardé).
    def retarget(markdown, old_title, new_title)
      old_key = key(old_title)
      markdown.to_s.gsub(PATTERN) do |match|
        title = Regexp.last_match(1)
        label = Regexp.last_match(2)
        next match unless key(title) == old_key

        label ? "[[#{new_title}|#{label}]]" : "[[#{new_title}]]"
      end
    end

    # Les pages qui renvoient à `page`, dans l'ordre du sommaire.
    def backlinks(page) = linking_to(page.title, except: page)

    def linking_to(title, except: nil)
      wanted = key(title)
      GuidePage.where.not(id: except&.id).where("guide_pages.body LIKE ?", "%[[%").includes(:chapter)
               .select { |other| targets(other.body).include?(wanted) }
               .sort_by { |other| [other.chapter.position, other.chapter.id, other.position, other.id] }
    end
  end
end
