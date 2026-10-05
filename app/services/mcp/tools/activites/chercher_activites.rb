module Mcp
  module Tools
    module Activites
      class ChercherActivites < Base
        include Commun

        tool "chercher_activites",
             title: "Chercher des activités",
             description: "Liste les activités proposées (balade avec les ânes, atelier…) : porteur, tarif, durée, " \
                          "publication sur le site, prochains créneaux et réservations à valider.",
             schema: { properties: { recherche: { type: "string", description: "Partie du nom (facultatif)." } } }

        def call(arguments)
          scope = activites.order(:name)
          if arguments["recherche"].present?
            scope = scope.where("experiences.name ILIKE ?", "%#{Experience.sanitize_sql_like(arguments['recherche'].strip)}%")
          end
          liste = scope.to_a
          return "Aucune activité." if liste.empty?

          a_venir = ExperienceAvailability.upcoming.reorder(nil).where(experience_id: liste.map(&:id)).group(:experience_id).count
          a_valider = ExperienceBooking.for_user(user).pending.reorder(nil).joins(:experience_availability)
                                       .where(experience_availabilities: { experience_id: liste.map(&:id) })
                                       .group("experience_availabilities.experience_id").count
          lignes = liste.map do |activite|
            "##{activite.id} #{activite.name} · porteur #{activite.human&.name || 'aucun'} · " \
              "#{Pricing::ExperienceLine.rate_label(activite)} · #{activite.public_duration_text.presence || 'durée ?'} · " \
              "#{activite.published_at ? 'publiée' : 'non publiée'} · #{a_venir[activite.id].to_i} créneau(x) à venir" \
              "#{" · #{a_valider[activite.id]} réservation(s) à valider" if a_valider[activite.id].to_i.positive?}"
          end
          "#{liste.size} activité(s) :\n#{lignes.join("\n")}"
        end
      end
    end
  end
end
