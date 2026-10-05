module Mcp
  module Tools
    module Activites
      # « Ajouter un créneau » sur la fiche d'une activité.
      class CreerCreneau < Ecriture
        include Commun

        tool "creer_creneau",
             title: "Créer un créneau d'activité",
             description: "Ouvre un créneau pour une activité : date, heure de début, durée et places (par défaut celles " \
                          "de l'activité). Le créneau doit tenir entre 8 h et 22 h sans chevaucher un autre créneau de la " \
                          "même activité le même jour. Aucun email.",
             schema: {
               properties: {
                 activite: ACTIVITE, date: DATE, heure: { type: "string", description: "Heure de début, « 14:00 »." },
                 duree_minutes: { type: "integer", description: "Par défaut, la durée de l'activité." },
                 places: { type: "integer", description: "Places maximum, par défaut celles de l'activité." },
                 notes: { type: "string" }
               },
               required: %w[activite date heure]
             }

        private

        def planifier(arguments)
          activite = activite!(arguments["activite"])
          jour = date!(arguments["date"], "date")
          raise Error, "Un porteur ne peut pas ouvrir de créneau dans le passé." if user.restricted_to_own_activities? && jour < Date.current

          attributs = { available_on: jour, starts_at: arguments["heure"].to_s.strip, duration_minutes: arguments["duree_minutes"].presence,
                        max_participants: arguments["places"].presence, notes: arguments["notes"].presence }.compact
          essai = activite.experience_availabilities.build(attributs)
          raise Error, "Créneau refusé : #{essai.errors.full_messages.to_sentence}" unless essai.valid?

          activite.experience_availabilities.reset
          Plan.new(resume: "Nouveau créneau : #{activite.name} le #{jour} à #{essai.starts_at}, #{essai.effective_duration} min, " \
                           "#{essai.effective_max_participants || 'sans limite de'} place(s)",
                   empreinte: [activite.id, attributs.transform_values(&:to_s)], donnees: { activite_id: activite.id, attributs: attributs })
        end

        def appliquer(plan)
          creneau = activite!(plan.donnees[:activite_id]).experience_availabilities.create!(plan.donnees[:attributs])
          "Créneau ouvert : #{ligne_creneau(creneau)}."
        end
      end
    end
  end
end
