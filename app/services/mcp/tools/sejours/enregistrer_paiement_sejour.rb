module Mcp
  module Tools
    module Sejours
      # « Ajouter un paiement » dans la modale séjour (`StayPaymentsController`).
      class EnregistrerPaiementSejour < Ecriture
        include Commun

        tool "enregistrer_paiement_sejour",
             title: "Enregistrer un paiement de séjour",
             description: "Ajoute un paiement à un séjour (virement reçu, espèces, carte) et recalcule son statut de " \
                          "paiement. Aucun email. Pour les comptes courants des habitants, c'est encoder_reglement.",
             schema: {
               properties: {
                 sejour: SEJOUR,
                 montant: { type: %w[number string], description: "Montant en euros, positif." },
                 methode: { type: "string", enum: %w[bank_transfer cash card stripe], description: "bank_transfer par défaut." },
                 statut: { type: "string", enum: %w[paid pending], description: "paid (reçu, défaut) ou pending (attendu)." },
                 date: DATE.merge(description: "Date de réception (AAAA-MM-JJ), aujourd'hui par défaut.")
               },
               required: %w[sejour montant]
             }

        private

        def planifier(arguments)
          stay = sejour!(arguments["sejour"])
          cents = cents!(arguments["montant"], "montant").abs
          methode = arguments["methode"].presence || "bank_transfer"
          statut_paiement = arguments["statut"].presence || "paid"
          paye_le = date_ou_nil(arguments["date"], "date") || Date.current
          if stay.direct_payments.where(amount_cents: cents, payment_method: methode, paid_on: paye_le)
                 .where("created_at > ?", 30.minutes.ago).exists?
            raise Error, "Un paiement identique vient d'être enregistré sur ce séjour : rien n'a été ajouté. Vérifie fiche_sejour."
          end

          attributs = { amount_cents: cents, payment_method: methode, status: statut_paiement, paid_on: paye_le }
          apres = simuler do
            enregistrer(Stay.find(stay.id), attributs)
            Stay.find(stay.id).balance_due_cents
          end
          Plan.new(
            resume: "#{ligne_sejour(stay)}\nPaiement de #{euros(cents)} · #{METHODES[methode]} · " \
                    "#{STATUTS_PAIEMENT[statut_paiement]} le #{paye_le}\nReste dû : #{euros(stay.balance_due_cents)} → #{euros(apres)}",
            empreinte: [etat(stay), attributs.transform_values(&:to_s)],
            donnees: { stay_id: stay.id, attributs: attributs }
          )
        end

        def appliquer(plan)
          stay = Stay.find(plan.donnees[:stay_id])
          paiement = enregistrer(stay, plan.donnees[:attributs])
          "Paiement ##{paiement.id} enregistré sur le séjour ##{stay.id}. Reste dû : #{euros(stay.reload.balance_due_cents)}."
        end

        def enregistrer(stay, attributs)
          paiement = Payment.create!(attributs.merge(stay: stay))
          stay.set_payment_status
          paiement
        end
      end
    end
  end
end
