module Mcp
  module Tools
    module Activites
      class RefuserReservationActivite < Ecriture
        include Commun

        tool "refuser_reservation_activite",
             title: "Refuser une réservation d'activité",
             description: "Refuse une réservation d'activité avec un motif. Un EMAIL PART AU CLIENT avec ce motif et " \
                          "l'invitation à choisir un autre créneau.",
             schema: {
               properties: { reservation: RESERVATION,
                             raison_client: { type: "string", description: "Motif, tel que le client le lira." } },
               required: %w[reservation raison_client]
             }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          resa = reservation!(arguments["reservation"])
          raison = arguments["raison_client"].to_s.strip
          raise Error, "Donne le motif du refus : il part au client." if raison.empty?
          raise Error, "Cette réservation est déjà #{resa.status_label.downcase}." if resa.refused? || resa.cancelled?

          email = email_client_activite(resa)
          Plan.new(resume: "#{ligne_reservation(resa)}\nRefus, motif : « #{raison} »\n" \
                           "#{email ? "Email au client (#{email})." : 'Aucun email ne pourra partir (client sans adresse).'}",
                   empreinte: [resa.id, resa.updated_at.to_f, raison], donnees: { id: resa.id, raison: raison })
        end

        def appliquer(plan)
          resa = reservation!(plan.donnees[:id])
          ExperienceBooking.transaction do
            resa.refuse!(plan.donnees[:raison])
            recalculer!(resa.stay)
          end
          ActivitySelectionMailer.booking_refused(resa).deliver_later
          "Réservation refusée : #{ligne_reservation(resa)}. Le client est prévenu."
        end
      end
    end
  end
end
