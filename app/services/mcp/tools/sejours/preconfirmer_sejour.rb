module Mcp
  module Tools
    module Sejours
      # « Pré-confirmer » (`Stays::PreConfirmer`) : l'équipe accepte la demande
      # et réclame l'acompte. Le séjour bloque alors le calendrier.
      class PreconfirmerSejour < Ecriture
        include Commun

        tool "preconfirmer_sejour",
             title: "Pré-confirmer un séjour",
             description: "Accepte une demande en attente et réclame l'acompte : crée un paiement en ligne en attente, " \
                          "passe le séjour en pré-confirmé (il bloque le calendrier) et ENVOIE AU CLIENT un email " \
                          "avec le lien de paiement. Sans montant, l'acompte suggéré par Claudy.",
             schema: {
               properties: {
                 sejour: SEJOUR,
                 acompte: { type: %w[number string], description: "Montant de l'acompte en euros (facultatif)." }
               },
               required: %w[sejour]
             }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          stay = sejour!(arguments["sejour"])
          raise Error, "Seule une demande en attente se pré-confirme (ce séjour est #{statut(stay)})." unless stay.status == "pending"

          email = email_client(stay) || raise(Error, "Ce client n'a pas d'adresse e-mail exploitable : la demande d'acompte ne pourrait pas partir.")
          cents = arguments["acompte"].present? ? cents!(arguments["acompte"], "acompte").abs : Stays::PreConfirmer.suggested_amount_cents(stay)
          raise Error, "Aucun acompte à suggérer : précise le montant." unless cents.positive?

          Plan.new(
            resume: "#{ligne_sejour(stay)}\nAcompte demandé : #{euros(cents)} (reste dû #{euros(stay.balance_due_cents)})\n" \
                    "Le séjour passe en pré-confirmé et bloque le calendrier.\n" \
                    "Un email avec le lien de paiement partira à #{email}.",
            empreinte: [etat(stay), cents],
            donnees: { stay_id: stay.id, cents: cents }
          )
        end

        def appliquer(plan)
          stay = Stay.find(plan.donnees[:stay_id])
          service = Stays::PreConfirmer.new(stay: stay, amount_cents: plan.donnees[:cents])
          raise Error, service.error_message unless service.run

          suite = service.email_error || "Demande d'acompte envoyée à #{stay.customer.email}."
          "Séjour ##{stay.id} pré-confirmé, paiement ##{service.payment.id} de #{euros(plan.donnees[:cents])} en attente. #{suite}"
        end
      end
    end
  end
end
