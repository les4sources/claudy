module Mcp
  module Tools
    module Guide
      # Ce que partagent les outils du Guide des 4 Sources (Michael,
      # 2026-10-19) : le manuel interne du collectif, en chapitres et pages
      # Markdown. Lire est ouvert à tous ; écrire demande le droit d'écrire
      # dans le Guide (`Access`, section :guide), comme à l'écran.
      module Commun
        PAGE = { type: %w[integer string], description: "Page du Guide : identifiant (#12, rendu par guide) ou titre exact." }.freeze
        CHAPITRE = { type: %w[integer string], description: "Chapitre : identifiant (#3, rendu par guide) ou titre exact." }.freeze
        POSITION = { type: "integer", minimum: 1, description: "Place dans la liste (1 = en premier). Défaut : à la fin." }.freeze
        MARKDOWN = "Markdown (CommonMark + tableaux et cases à cocher « - [ ] »). La page a déjà son titre : " \
                   "les intertitres commencent à « ## ». Pas de HTML brut (il n'est pas rendu)."

        # Les outils qui écrivent : refusés à qui ne peut pas écrire dans le
        # Guide à l'écran.
        module Redacteur
          def call(arguments)
            raise Base::Error, "Seuls les Sourciers modifient le Guide, comme dans Claudy." unless user.can_write?(:guide)

            super
          end
        end

        def self.included(base)
          base.prepend(Redacteur) if base < Ecriture
        end

        private

        def id_ou_nil(reference)
          texte = reference.to_s.strip.delete_prefix("#")
          texte.match?(/\A\d+\z/) ? texte.to_i : nil
        end

        def page!(reference)
          raise Base::Error, "Précise la page (identifiant ou titre)." if reference.blank?

          id = id_ou_nil(reference)
          return GuidePage.includes(:chapter).find_by(id: id) || raise(Base::Error, "Aucune page ##{id} dans le Guide.") if id

          trouvees = GuidePage.includes(:chapter).where("title ILIKE ?", "%#{GuidePage.sanitize_sql_like(reference.to_s.strip)}%").to_a
          exacte = trouvees.select { |page| page.title.casecmp?(reference.to_s.strip) }
          trouvees = exacte if exacte.one?
          return trouvees.first if trouvees.one?
          raise Base::Error, "Aucune page du Guide ne s'appelle « #{reference} »." if trouvees.empty?

          raise Base::Error, "Plusieurs pages correspondent à « #{reference} » : " \
                             "#{trouvees.first(10).map { |p| "##{p.id} #{p.title}" }.join(', ')}."
        end

        def chapitre!(reference)
          raise Base::Error, "Précise le chapitre (identifiant ou titre)." if reference.blank?

          id = id_ou_nil(reference)
          return GuideChapter.find_by(id: id) || raise(Base::Error, "Aucun chapitre ##{id} dans le Guide.") if id

          trouves = GuideChapter.where("title ILIKE ?", "%#{GuideChapter.sanitize_sql_like(reference.to_s.strip)}%").to_a
          exact = trouves.select { |chapitre| chapitre.title.casecmp?(reference.to_s.strip) }
          trouves = exact if exact.one?
          return trouves.first if trouves.one?
          raise Base::Error, "Aucun chapitre du Guide ne s'appelle « #{reference} »." if trouves.empty?

          raise Base::Error, "Plusieurs chapitres correspondent à « #{reference} » : " \
                             "#{trouves.map { |c| "##{c.id} #{c.title}" }.join(', ')}."
        end

        def ligne_page(page)
          edition = page.last_edited_at && " · modifiée le #{I18n.l(page.last_edited_at, format: '%d/%m/%Y')}" \
                                           "#{" par #{page.last_editor.display_name}" if page.last_editor}"
          "Page ##{page.id} « #{page.title} »#{edition}"
        end

        def lien_page(page)
          options = ActionMailer::Base.default_url_options
          helpers = Rails.application.routes.url_helpers
          options[:host].present? ? helpers.guide_page_url(page, **options) : helpers.guide_page_path(page)
        end

        # Place `element` à `position` (1 = en premier) parmi `elements`, et
        # rend la liste des identifiants dans le nouvel ordre.
        def ordre_avec(elements, element, position)
          ids = elements.map(&:id) - [element.id]
          index = position.to_i.clamp(1, ids.size + 1) - 1
          ids.insert(index, element.id)
        end
      end
    end
  end
end
