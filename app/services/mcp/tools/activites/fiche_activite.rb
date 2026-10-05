module Mcp
  module Tools
    module Activites
      class FicheActivite < Base
        include Commun

        tool "fiche_activite",
             title: "Fiche d'une activité",
             description: "Le détail d'une activité : porteur, équipe, tarif, durée, participants, rémunération du " \
                          "porteur, publication, et ses créneaux (à venir par défaut) avec les réservations de chacun.",
             schema: {
               properties: {
                 activite: ACTIVITE,
                 passes: { type: "boolean", description: "Montrer aussi les créneaux passés des 90 derniers jours." }
               },
               required: %w[activite]
             }

        def call(arguments)
          activite = activite!(arguments["activite"])
          lignes = ["Activité ##{activite.id} — #{activite.name}"]
          lignes << "Porteur : #{activite.human&.name || 'aucun'}#{" · équipe : #{activite.team.name}" if activite.try(:team)}"
          lignes << "Tarif : #{Pricing::ExperienceLine.rate_label(activite)} · durée : #{activite.public_duration_text.presence || '?'}" \
                    "#{" (#{activite.duration_hours} h payées au porteur)" if activite.duration_hours}"
          lignes << "Participants : #{activite.min_participants || '?'} à #{activite.max_participants || 'sans limite'}"
          lignes << "Rémunération du porteur : #{euros(activite.effective_carrier_hourly_cents)}/h" \
                    "#{' (tarif propre)' if activite.carrier_rate_overridden?}"
          lignes << (activite.published_at ? "Publiée sur le site (#{activite.slug})" : "Non publiée sur le site")
          lignes << "Résumé : #{activite.summary}" if activite.summary.present?

          creneaux = activite.experience_availabilities.includes(experience_bookings: { stay: :customer })
          creneaux = arguments["passes"] ? creneaux.where("available_on >= ?", Date.current - 90) : creneaux.upcoming
          creneaux = creneaux.order(:available_on, :starts_at).limit(60).to_a
          lignes << (creneaux.empty? ? "Aucun créneau." : "Créneaux :")
          creneaux.each do |creneau|
            creneau.experience = activite
            lignes << "- #{ligne_creneau(creneau)}#{" · #{creneau.notes}" if creneau.notes.present?}"
            creneau.experience_bookings.sort_by(&:id).each { |resa| lignes << "    #{ligne_reservation(resa)}" }
          end
          lignes.join("\n")
        end
      end
    end
  end
end
