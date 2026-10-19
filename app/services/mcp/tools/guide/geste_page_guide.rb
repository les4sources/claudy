module Mcp
  module Tools
    module Guide
      # Retirer une page du Guide, ou la ramener à une version passée
      # (Guide::PagesController#destroy, Guide::RevisionsController#restore).
      class GestePageGuide < Ecriture
        include Commun

        GESTES = %w[restaurer retirer].freeze

        tool "geste_page_guide",
             title: "Restaurer ou retirer une page du Guide",
             description: "restaurer : la page reprend le titre et le contenu de `version` (numéro rendu par page_guide " \
                          "avec historique) ; cela ajoute une version, rien n'est effacé. retirer (motif obligatoire) : " \
                          "la page disparaît du Guide (suppression douce, son historique est gardé).",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES },
                 page: PAGE,
                 version: { type: "integer", minimum: 1, description: "Pour restaurer : le numéro de version." }
               },
               required: %w[geste page]
             }

        private

        def planifier(arguments)
          page = page!(arguments["page"])
          case arguments["geste"]
          when "restaurer" then plan_restauration(page, arguments["version"].to_i)
          when "retirer"
            motif!({ "motif" => @motif })
            Plan.new(resume: "RETIRER du Guide : #{ligne_page(page)} (chapitre « #{page.chapter.title} »).",
                     empreinte: [page.id, page.updated_at.to_f, :retirer], donnees: { page: page.id, retirer: true })
          else raise Error, "Geste inconnu : « #{arguments['geste']} ». Gestes : #{GESTES.join(', ')}."
          end
        end

        def appliquer(plan)
          page = GuidePage.find(plan.donnees[:page])
          if plan.donnees[:retirer]
            page.soft_delete!(validate: false)
            return "Page ##{page.id} « #{page.title} » retirée du Guide (suppression douce)."
          end

          revision = GuidePageRevision.find(plan.donnees[:revision])
          ::Guide::SavePage.new(page, user: user, source: "mcp")
                           .call(title: revision.title, body: revision.body,
                                 summary: ["Retour à la version #{revision.number}", @motif.presence].compact.join(" — "))
          "#{ligne_page(page.reload)} — revenue à la version #{revision.number} (#{page.revisions.size} versions)."
        end

        def plan_restauration(page, numero)
          revisions = page.revisions.reorder(:created_at, :id).to_a
          revision = revisions[numero - 1] if numero.positive?
          raise Error, "Donne une version entre 1 et #{revisions.size}." if revision.nil?
          raise Error, "La page est déjà dans l'état de la version #{numero}." if revision.title == page.title && revision.body == page.body

          resume = "RESTAURER #{ligne_page(page)}\nÀ la version #{numero} du #{I18n.l(revision.created_at, format: '%d/%m/%Y %H:%M')} " \
                   "par #{revision.author_name} (titre « #{revision.title} », #{revision.body.lines.size} ligne(s))."
          Plan.new(resume: resume, empreinte: [page.id, page.updated_at.to_f, revision.id],
                   donnees: { page: page.id, revision: revision.id })
        end
      end
    end
  end
end
