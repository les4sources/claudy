module Mcp
  module Tools
    module Sejours
      # Le bouton de statut de la modale séjour (`Stays::QuickStatusUpdater`).
      class ChangerStatutSejour < Ecriture
        include Commun

        tool "changer_statut_sejour",
             title: "Changer le statut d'un séjour",
             description: "Passe un séjour en attente, confirmé ou annulé, comme le bouton de la fiche séjour. " \
                          "CONFIRMER envoie au client l'email « votre séjour est confirmé » (une seule fois) ; pour un séjour " \
                          "déjà passé, rien ne part sauf avec `envoyer_email`. " \
                          "ANNULER n'écrit pas au client, annule ses activités et retire ses paiements en attente ; " \
                          "pour refuser une demande en prévenant le client, utilise refuser_sejour.",
             schema: {
               properties: {
                 sejour: SEJOUR,
                 statut: { type: "string", enum: Stay::STATUSES_QUICK_SETTABLE, description: "pending, confirmed ou canceled." },
                 envoyer_email: { type: "boolean", description: "Confirmation d'un séjour déjà passé : true envoie quand même l'email au client (comme la modale de la fiche)." }
               },
               required: %w[sejour statut]
             }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          stay = sejour!(arguments["sejour"])
          cible = arguments["statut"].to_s
          raise Error, "Statut inconnu « #{cible} » (#{Stay::STATUSES_QUICK_SETTABLE.join(', ')})." unless Stay::STATUSES_QUICK_SETTABLE.include?(cible)
          raise Error, "Le séjour ##{stay.id} est déjà #{statut(stay)}." if stay.status == cible || (cible == "canceled" && stay.canceled?)

          envoyer = cible == "confirmed" && arguments["envoyer_email"] == true && passe?(stay)
          effets = []
          if envoyer
            effets << (email_client(stay) ? "Séjour passé : l'email « votre séjour est confirmé » partira quand même à #{email_client(stay)}." : "Aucun email ne partira (client sans adresse exploitable).")
          elsif cible == "confirmed"
            effets << (email_confirmation(stay) || "Aucun email ne partira (#{raison_sans_email(stay)}).")
          end
          if cible == "canceled"
            activites = stay.experience_bookings.active.count
            en_attente = stay.payments.pending.to_a
            effets << "#{activites} activité(s) annulée(s)." if activites.positive?
            effets << "Paiement(s) en attente retiré(s) : #{en_attente.map { |p| "##{p.id} #{euros(p.amount_cents)}" }.join(', ')}." if en_attente.any?
            effets << "Le client n'est pas prévenu."
          end

          Plan.new(
            resume: "#{ligne_sejour(stay)}\nStatut : #{statut(stay)} → #{STATUTS[cible]}\n#{effets.join("\n")}".strip,
            empreinte: [etat(stay), cible, envoyer],
            donnees: { stay_id: stay.id, statut: cible, envoyer_email: envoyer }
          )
        end

        def appliquer(plan)
          stay = Stay.find(plan.donnees[:stay_id])
          envoye_avant = stay.confirmation_email_sent_at
          updater = Stays::QuickStatusUpdater.new(stay: stay, status: plan.donnees[:statut],
                                                  notify_customer: plan.donnees[:envoyer_email] ? true : nil)
          raise Error, updater.error_message unless updater.run

          stay.reload
          email = stay.confirmation_email_sent_at != envoye_avant ? " Email de confirmation envoyé à #{stay.customer.email}." : ""
          "Séjour ##{stay.id} : #{statut(stay)}.#{email}"
        end

        def email_confirmation(stay)
          return nil if stay.confirmation_email_sent_at.present? || passe?(stay) || email_client(stay).nil?

          "Un email « votre séjour est confirmé » partira à #{email_client(stay)}."
        end

        def passe?(stay)
          stay.departure_date.present? && stay.departure_date < Date.current
        end

        def raison_sans_email(stay)
          return "déjà envoyé le #{stay.confirmation_email_sent_at.to_date}" if stay.confirmation_email_sent_at
          return "séjour terminé, `envoyer_email: true` pour l'envoyer quand même" if passe?(stay)

          "client sans adresse exploitable"
        end
      end
    end
  end
end
