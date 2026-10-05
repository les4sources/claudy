module Mcp
  module Tools
    module Activites
      class ModifierReservationActivite < Ecriture
        include Commun

        tool "modifier_reservation_activite",
             title: "Modifier une réservation d'activité",
             description: "Change le nombre de participants d'une réservation d'activité ; le total du séjour suit. " \
                          "Aucun email.",
             schema: {
               properties: { reservation: RESERVATION, participants: { type: "integer" } },
               required: %w[reservation participants]
             }

        private

        def planifier(arguments)
          resa = reservation!(arguments["reservation"])
          participants = arguments["participants"].to_i
          raise Error, "Donne un nombre de participants." unless participants.positive?
          raise Error, "La réservation compte déjà #{participants} participant(s)." if resa.participants == participants

          stay = resa.stay
          apres = simuler do
            changer(resa.id, participants)
            Stay.find(stay.id).total_amount_cents
          end
          Plan.new(
            resume: "#{ligne_reservation(resa)}\nParticipants : #{resa.participants} → #{participants}\n" \
                    "Total du séjour ##{stay.id} : #{euros(stay.total_amount_cents)} → #{euros(apres)}",
            empreinte: [resa.id, resa.updated_at.to_f, participants],
            donnees: { id: resa.id, participants: participants }
          )
        end

        def appliquer(plan)
          resa = changer(plan.donnees[:id], plan.donnees[:participants])
          "Réservation mise à jour : #{ligne_reservation(resa)}."
        end

        def changer(id, participants)
          resa = reservation!(id)
          resa.capacity_override = true
          resa.update!(participants: participants)
          recalculer!(resa.stay)
          resa
        end
      end
    end
  end
end
