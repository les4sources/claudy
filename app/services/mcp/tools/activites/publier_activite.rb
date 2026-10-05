module Mcp
  module Tools
    module Activites
      # Publier / dépublier sur le site (Experiences::PublishService), ou mettre
      # une activité au rebut.
      class PublierActivite < Ecriture
        include Commun

        tool "publier_activite",
             title: "Publier, dépublier ou supprimer une activité",
             description: "publier : l'activité apparaît sur le site des 4 Sources (reconstruit automatiquement). " \
                          "depublier : elle en disparaît. supprimer : elle quitte Claudy (suppression douce, " \
                          "refusée tant qu'elle a des créneaux à venir).",
             schema: {
               properties: {
                 activite: ACTIVITE,
                 action: { type: "string", enum: %w[publier depublier supprimer] },
                 slug: { type: "string", description: "Adresse sur le site (publier), facultatif." }
               },
               required: %w[activite action]
             }

        private

        def planifier(arguments)
          equipe!
          activite = activite!(arguments["activite"])
          action = arguments["action"].to_s
          case action
          when "publier" then raise Error, "Déjà publiée." if activite.published_at && arguments["slug"].blank?
          when "depublier" then raise Error, "Elle n'est pas publiée." unless activite.published_at
          when "supprimer"
            motif!(arguments)
            a_venir = activite.experience_availabilities.upcoming.count
            raise Error, "Elle a encore #{a_venir} créneau(x) à venir : supprime-les d'abord." if a_venir.positive?
          else raise Error, "action : publier, depublier ou supprimer."
          end

          Plan.new(resume: "#{action.capitalize} « #{activite.name} »#{" (adresse #{arguments['slug']})" if arguments['slug'].present?}",
                   empreinte: [activite.id, activite.updated_at.to_f, action, arguments["slug"].to_s],
                   donnees: { id: activite.id, action: action, slug: arguments["slug"].presence })
        end

        def appliquer(plan)
          activite = activite!(plan.donnees[:id])
          case plan.donnees[:action]
          when "publier" then Experiences::PublishService.new(experience: activite).publish!(slug: plan.donnees[:slug])
          when "depublier" then Experiences::PublishService.new(experience: activite).unpublish!
          else activite.soft_delete!(validate: false)
          end
          "« #{activite.name} » : #{plan.donnees[:action]} fait."
        end
      end
    end
  end
end
