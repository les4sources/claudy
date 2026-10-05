module Mcp
  module Tools
    module Activites
      # Le bouton « Valider » du porteur (ExperienceBookingsController#confirm).
      class ValiderReservationActivite < Ecriture
        include Commun

        tool "valider_reservation_activite",
             title: "Valider une réservation d'activité",
             description: "Valide une réservation en attente : elle devient exigible dans le solde du séjour et un " \
                          "EMAIL PART AU CLIENT. Sur un créneau déjà passé, valider constate qu'elle a eu lieu, sans email.",
             schema: { properties: { reservation: RESERVATION }, required: %w[reservation] }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          resa = reservation!(arguments["reservation"])
          raise Error, "Seule une réservation à valider se valide (celle-ci est #{resa.status_label.downcase})." unless resa.pending?

          avis = if !resa.slot_in_the_future? then "Créneau passé : elle sera aussi déclarée « a eu lieu ». Aucun email."
                 elsif (email = email_client_activite(resa)) then "Un email de confirmation part au client (#{email})."
                 else "Aucun email ne pourra partir (client sans adresse)."
                 end
          sans_duree = resa.experience.duration_hours.blank? ? "\n⚠ L'activité n'a pas de durée en heures : la rémunération du porteur ne pourra pas être calculée." : ""
          Plan.new(resume: "#{ligne_reservation(resa)}\n#{avis}#{sans_duree}",
                   empreinte: [resa.id, resa.updated_at.to_f], donnees: { id: resa.id })
        end

        def appliquer(plan)
          resa = reservation!(plan.donnees[:id])
          apres_coup = !resa.slot_in_the_future?
          ExperienceBooking.transaction do
            resa.confirm!
            resa.mark_held!(by: user.human) if apres_coup
            recalculer!(resa.stay)
          end
          ActivitySelectionMailer.booking_confirmed(resa).deliver_later unless apres_coup
          "Réservation validée : #{ligne_reservation(resa)}.#{apres_coup ? '' : ' Le client est prévenu.'}"
        end
      end
    end
  end
end
