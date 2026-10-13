module Mcp
  module Tools
    module Activites
      class ModifierReservationActivite < Ecriture
        include Commun

        tool "modifier_reservation_activite",
             title: "Modifier une réservation d'activité",
             description: "Change le nombre de participants d'une réservation d'activité (le total du séjour suit), " \
                          "qui l'a tenue (`tenue_par`, vide = le porteur de l'activité) ou ce qu'on lui doit " \
                          "(`remuneration`, en euros). Figé une fois la prestation sur un relevé. Aucun email.",
             schema: {
               properties: {
                 reservation: RESERVATION, participants: { type: "integer" },
                 tenue_par: TENUE_PAR, remuneration: REMUNERATION
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

          if arguments.key?("tenue_par") || arguments.key?("remuneration")
            equipe!
            raise Error, "Cette prestation figure sur un relevé : qui la reçoit et combien sont figés." if resa.carrier_statement

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
