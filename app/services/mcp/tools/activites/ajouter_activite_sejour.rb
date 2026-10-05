module Mcp
  module Tools
    module Activites
      # « Ajouter une activité » sur la fiche séjour (ExperienceBookingsController#create).
      class AjouterActiviteSejour < Ecriture
        include Commun
        include Sejours::Commun

        tool "ajouter_activite_sejour",
             title: "Ajouter une activité à un séjour",
             description: "Inscrit un séjour sur un créneau d'activité (voir disponibilites ou fiche_activite). « pending » " \
                          "(défaut) attend la validation du porteur ; « confirmed » l'inscrit d'office et ENVOIE UN EMAIL " \
                          "AU CLIENT. L'équipe peut dépasser la capacité du créneau ; l'aperçu le signale.",
             schema: {
               properties: {
                 sejour: Sejours::Commun::SEJOUR, creneau: CRENEAU,
                 participants: { type: "integer" },
                 statut: { type: "string", enum: ExperienceBooking::ADMIN_CREATABLE_STATUSES, description: "pending (défaut) ou confirmed." }
               },
               required: %w[sejour creneau participants]
             }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          equipe!
          stay = sejour!(arguments["sejour"])
          creneau = creneau!(arguments["creneau"])
          participants = arguments["participants"].to_i
          raise Error, "Donne un nombre de participants." unless participants.positive?

          statut_cible = ExperienceBooking::ADMIN_CREATABLE_STATUSES.include?(arguments["statut"]) ? arguments["statut"] : "pending"
          places = creneau.available_spots
          apres = simuler do
            inscrire(Stay.find(stay.id), creneau, participants, statut_cible)
            Stay.find(stay.id).total_amount_cents
          end
          email = email_client_activite(ExperienceBooking.new(stay: stay))
          avis = if statut_cible == "pending" then "Le porteur devra la valider ; aucun email pour l'instant."
                 elsif email then "Un email part au client (#{email})."
                 else "Aucun email ne pourra partir (client sans adresse)."
                 end
          depassement = places && participants > places ? "\n⚠ Dépasse la capacité : #{places} place(s) libre(s) seulement." : ""
          Plan.new(
            resume: "#{ligne_sejour(stay)}\n+ #{ligne_creneau(creneau)}\n#{participants} participant(s), " \
                    "#{ExperienceBooking::STATUS_LABELS[statut_cible]}#{depassement}\n" \
                    "Total du séjour : #{euros(stay.total_amount_cents)} → #{euros(apres)}\n#{avis}",
            empreinte: [etat(stay), creneau.id, creneau.booked_participants, participants, statut_cible],
            donnees: { stay_id: stay.id, creneau_id: creneau.id, participants: participants, statut: statut_cible }
          )
        end

        def appliquer(plan)
          d = plan.donnees
          stay = Stay.find(d[:stay_id])
          resa = inscrire(stay, creneau!(d[:creneau_id]), d[:participants], d[:statut])
          ActivitySelectionMailer.booking_added_by_team(resa).deliver_later if resa.confirmed?
          "Activité ajoutée : #{ligne_reservation(resa)}. Total du séjour : #{euros(stay.reload.total_amount_cents)}."
        end

        def inscrire(stay, creneau, participants, statut)
          resa = stay.experience_bookings.new(experience_availability: creneau, participants: participants, status: statut)
          resa.capacity_override = true
          resa.save!
          recalculer!(stay)
          resa
        end
      end
    end
  end
end
