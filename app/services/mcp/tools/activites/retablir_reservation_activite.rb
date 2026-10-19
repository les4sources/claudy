module Mcp
  module Tools
    module Activites
      # « Rétablir » une activité retirée d'un séjour (ExperienceBookingsController#restore).
      class RetablirReservationActivite < Ecriture
        include Commun

        tool "retablir_reservation_activite",
             title: "Rétablir une activité retirée",
             description: "Remet sur son séjour une réservation d'activité retirée par erreur (annulée) : elle reprend " \
                          "son statut d'avant le retrait et revient dans le total. Ni le client ni le porteur ne sont " \
                          "prévenus ; la rémunération déjà relevée n'est pas payée une seconde fois.",
             schema: { properties: { reservation: RESERVATION }, required: %w[reservation] }

        private

        def planifier(arguments)
          equipe!
          resa = reservation!(arguments["reservation"])
          raise Error, "Seule une réservation retirée se rétablit (celle-ci est #{resa.status_label.downcase})." unless resa.cancelled?

          stay = resa.stay
          statut = ExperienceBooking::STATUS_LABELS[resa.status_before_cancellation]
          apres = simuler do
            retablir(resa.id)
            Stay.find(stay.id).total_amount_cents
          end
          Plan.new(resume: "#{ligne_reservation(resa)}\nRétablie, statut « #{statut} ». Total du séjour ##{stay.id} : " \
                           "#{euros(stay.total_amount_cents)} → #{euros(apres)}. Personne n'est prévenu.",
                   empreinte: [resa.id, resa.updated_at.to_f], donnees: { id: resa.id })
        end

        def appliquer(plan)
          resa = retablir(plan.donnees[:id])
          "Activité rétablie : #{ligne_reservation(resa)}."
        end

        def retablir(id)
          resa = reservation!(id)
          resa.restore!
          recalculer!(resa.stay)
          resa
        end
      end
    end
  end
end
