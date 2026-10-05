module Mcp
  module Tools
    module Activites
      # « Retirer » une activité d'un séjour : elle passe en annulée, sort du total.
      class AnnulerReservationActivite < Ecriture
        include Commun

        tool "annuler_reservation_activite",
             title: "Retirer une activité d'un séjour",
             description: "Annule une réservation d'activité (elle sort du total du séjour, l'historique la garde). " \
                          "Ni le client ni le porteur ne sont prévenus. Pour refuser en prévenant le client, " \
                          "utilise refuser_reservation_activite.",
             schema: { properties: { reservation: RESERVATION }, required: %w[reservation] }

        private

        def planifier(arguments)
          equipe!
          resa = reservation!(arguments["reservation"])
          raise Error, "Cette réservation est déjà #{resa.status_label.downcase}." if resa.cancelled? || resa.refused?

          stay = resa.stay
          apres = simuler do
            annuler(resa.id)
            Stay.find(stay.id).total_amount_cents
          end
          Plan.new(resume: "#{ligne_reservation(resa)}\nAnnulée. Total du séjour ##{stay.id} : " \
                           "#{euros(stay.total_amount_cents)} → #{euros(apres)}. Personne n'est prévenu.",
                   empreinte: [resa.id, resa.updated_at.to_f], donnees: { id: resa.id })
        end

        def appliquer(plan)
          resa = annuler(plan.donnees[:id])
          "Activité retirée : #{ligne_reservation(resa)}."
        end

        def annuler(id)
          resa = reservation!(id)
          resa.update!(status: "cancelled")
          recalculer!(resa.stay)
          resa
        end
      end
    end
  end
end
