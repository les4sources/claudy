module Mcp
  module Tools
    module Sejours
      # La demande de modification qu'un client envoie depuis sa page de séjour
      # (issue #133) : rien ne change tant que l'équipe ne l'a pas approuvée.
      class TraiterDemandeModification < Ecriture
        include Commun

        tool "traiter_demande_modification",
             title: "Traiter une demande de modification",
             description: "Approuve ou refuse la demande de modification en attente d'un séjour (voir fiche_sejour). " \
                          "Approuver applique la nouvelle composition et le nouveau total ; refuser exige un motif. " \
                          "Dans les deux cas, un email PART AU CLIENT.",
             schema: {
               properties: {
                 sejour: SEJOUR,
                 decision: { type: "string", enum: %w[approuver refuser] },
                 raison_client: { type: "string", description: "Motif du refus, envoyé au client (obligatoire pour refuser)." },
                 forcer_dispo: { type: "boolean", description: "Approuver même si le gîte n'est plus libre." }
               },
               required: %w[sejour decision]
             }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          stay = sejour!(arguments["sejour"])
          demande = stay.stay_change_requests.pending.order(:created_at).last ||
                    raise(Error, "Aucune demande de modification en attente sur le séjour ##{stay.id}.")
          decision = arguments["decision"].to_s
          raison = arguments["raison_client"].to_s.strip
          raise Error, "decision : approuver ou refuser." unless %w[approuver refuser].include?(decision)
          raise Error, "Un motif est obligatoire pour refuser : il part au client." if decision == "refuser" && raison.empty?

          if decision == "approuver" && arguments["forcer_dispo"] != true &&
             !Stays::LodgingAvailability.call(stay: stay, draft: demande.proposed_draft)
            raise Error, "Le gîte n'est plus libre pour les dates demandées. Refuse la demande, ou approuve avec forcer_dispo."
          end

          email = email_client(stay) ? "Email au client (#{email_client(stay)})." : "Aucun email ne pourra partir (client sans adresse)."
          detail = if decision == "approuver"
                     "Approbation : total #{euros(stay.total_amount_cents)} → #{euros(demande.new_total_cents)}" \
                       "#{" — remboursement de #{euros(demande.overpaid_cents)} à faire (IBAN #{demande.refund_iban})" if demande.refund_expected?}"
                   else
                     "Refus, motif : « #{raison} »"
                   end
          Plan.new(resume: "#{ligne_sejour(stay)}\nDemande ##{demande.id} du #{demande.created_at.to_date}\n#{detail}\n#{email}",
                   empreinte: [etat(stay), demande.id, demande.updated_at.to_f, decision, raison],
                   donnees: { demande_id: demande.id, decision: decision, raison: raison, forcer: arguments["forcer_dispo"] == true })
        end

        def appliquer(plan)
          demande = StayChangeRequest.pending.find(plan.donnees[:demande_id])
          if plan.donnees[:decision] == "approuver"
            service = Stays::ApplyChangeRequest.new(change_request: demande, user: user, force_availability: plan.donnees[:forcer])
            raise Error, service.error_message unless service.run

            StayChangeRequestMailer.customer_approved(demande).deliver_later
            "Demande ##{demande.id} approuvée : nouveau total #{euros(demande.stay.reload.total_amount_cents)}. Le client est prévenu."
          else
            demande.update!(status: "refused", refusal_reason: plan.donnees[:raison])
            StayChangeRequestMailer.customer_refused(demande).deliver_later
            "Demande ##{demande.id} refusée. Le client est prévenu."
          end
        end
      end
    end
  end
end
