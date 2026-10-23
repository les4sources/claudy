module Mcp
  module Tools
    module Activites
      class ModifierReservationActivite < Ecriture
        include Commun

        tool "modifier_reservation_activite",
             title: "Modifier une réservation d'activité",
             description: "Change le nombre de participants d'une réservation d'activité (le total du séjour suit), " \
                          "qui l'a tenue (`tenue_par`, vide = le porteur de l'activité), combien de temps elle a " \
                          "réellement duré (`duree_effective`, la rémunération suit) ou ce qu'on lui doit " \
                          "(`remuneration`, en euros). Figé une fois la prestation sur un relevé. Aucun email.",
             schema: {
               properties: {
                 reservation: RESERVATION, participants: { type: "integer" },
                 tenue_par: TENUE_PAR, duree_effective: DUREE_EFFECTIVE, remuneration: REMUNERATION
               },
               required: %w[reservation]
             }

        private

        def planifier(arguments)
          resa = reservation!(arguments["reservation"])
          changements = {}
          lignes = []

          if arguments.key?("participants")
            participants = arguments["participants"].to_i
            raise Error, "Donne un nombre de participants." unless participants.positive?

            if participants != resa.participants
              changements[:participants] = participants
              lignes << "Participants : #{resa.participants} → #{participants}"
            end
          end

          if arguments.key?("tenue_par") || arguments.key?("remuneration") || arguments.key?("duree_effective")
            equipe!
            raise Error, "Cette prestation figure sur un relevé : qui la reçoit, sa durée et combien sont figés." if resa.carrier_statement

            if arguments.key?("duree_effective")
              minutes = ExperienceBooking.parse_duration(arguments["duree_effective"])
              raise Error, "Durée illisible : « #{arguments['duree_effective']} » (exemples : 1h30, 1,5, 90 min)." if minutes == :invalid
              raise Error, "La durée effective doit être positive." if minutes&.<=(0)

              minutes = nil if minutes == resa.planned_duration_minutes
              if minutes != resa.duration_minutes
                changements[:duration_minutes] = minutes
                lignes << "Durée : #{resa.effective_duration || '—'} → " \
                          "#{ExperienceBooking.format_duration(minutes || resa.planned_duration_minutes) || '—'}"
              end
            end

            if arguments.key?("tenue_par")
              humain = tenue_par!(arguments["tenue_par"], resa.experience)
              if humain&.id != resa.performed_by_id
                changements[:performed_by_id] = humain&.id
                lignes << "Tenue par : #{resa.carrier&.name || '—'} → #{humain&.name || resa.experience.human&.name || '—'}"
              end
            end
            if arguments.key?("remuneration")
              cents = remuneration_cents!(arguments["remuneration"])
              if cents != resa.carrier_fee_cents
                changements[:carrier_fee_cents] = cents
                lignes << "Rémunération : #{resa.carrier_fee_cents ? euros(resa.carrier_fee_cents) : '—'} → " \
                          "#{cents ? euros(cents) : 'tarif horaire × durée'}"
              end
            end
          end
          raise Error, "Rien à changer sur la réservation ##{resa.id}." if changements.empty?

          if changements.key?(:duration_minutes) && !changements.key?(:carrier_fee_cents) && resa.confirmed?
            apres = simuler { changer(resa.id, changements).carrier_fee_cents }
            lignes << "Rémunération : #{resa.carrier_fee_cents ? euros(resa.carrier_fee_cents) : '—'} → #{apres ? euros(apres) : '—'}"
          end

          stay = resa.stay
          if changements.key?(:participants)
            apres = simuler do
              changer(resa.id, changements)
              Stay.find(stay.id).total_amount_cents
            end
            lignes << "Total du séjour ##{stay.id} : #{euros(stay.total_amount_cents)} → #{euros(apres)}"
          end
          Plan.new(
            resume: "#{ligne_reservation(resa)}\n#{lignes.join("\n")}",
            empreinte: [resa.id, resa.updated_at.to_f, changements.to_a],
            donnees: { id: resa.id, changements: changements }
          )
        end

        def appliquer(plan)
          resa = changer(plan.donnees[:id], plan.donnees[:changements])
          "Réservation mise à jour : #{ligne_reservation(resa)}."
        end

        def changer(id, changements)
          resa = reservation!(id)
          resa.capacity_override = true
          resa.update!(changements.transform_keys(&:to_sym))
          recalculer!(resa.stay)
          resa
        end
      end
    end
  end
end
