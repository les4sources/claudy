module Mcp
  module Tools
    module Sejours
      # La ligne de paiement éditable de la modale séjour : statut, montant,
      # méthode, date. Seuls les paiements rattachés directement au séjour.
      class ModifierPaiementSejour < Ecriture
        include Commun

        tool "modifier_paiement_sejour",
             title: "Modifier un paiement de séjour",
             description: "Corrige un paiement d'un séjour (identifiant rendu par fiche_sejour) : le marquer payé, " \
                          "en attente ou remboursé, changer son montant, sa méthode ou sa date. Aucun email.",
             schema: {
               properties: {
                 sejour: SEJOUR,
                 paiement: { type: %w[integer string], description: "Identifiant du paiement (#812)." },
                 statut: { type: "string", enum: %w[paid pending refunded] },
                 montant: { type: %w[number string], description: "Nouveau montant en euros." },
                 methode: { type: "string", enum: %w[bank_transfer cash card stripe] },
                 date: DATE.merge(description: "Date de paiement (AAAA-MM-JJ).")
               },
               required: %w[sejour paiement]
             }

        private

        def planifier(arguments)
          stay = sejour!(arguments["sejour"])
          id = identifiant!(arguments["paiement"], "paiement")
          paiement = stay.direct_payments.find_by(id: id) ||
                     raise(Error, "Le paiement ##{id} n'est pas rattaché directement au séjour ##{stay.id} " \
                                  "(un paiement de la réservation d'origine se corrige dans son propre écran).")
          changements = {}
          changements[:status] = arguments["statut"] if arguments["statut"].present?
          changements[:amount_cents] = cents!(arguments["montant"], "montant").abs if arguments["montant"].present?
          changements[:payment_method] = arguments["methode"] if arguments["methode"].present?
          changements[:paid_on] = date!(arguments["date"], "date") if arguments["date"].present?
          changements.reject! { |champ, valeur| paiement.public_send(champ) == valeur }
          raise Error, "Rien à changer sur le paiement ##{id}." if changements.empty?

          libelles = changements.map { |champ, valeur| "#{champ} : #{paiement.public_send(champ)} → #{valeur}" }
          apres = simuler do
            appliquer_sur(Stay.find(stay.id), id, changements)
            Stay.find(stay.id).balance_due_cents
          end
          Plan.new(
            resume: "#{ligne_sejour(stay)}\nPaiement ##{id} (#{euros(paiement.amount_cents)}) : #{libelles.join(', ')}\n" \
                    "Reste dû : #{euros(stay.balance_due_cents)} → #{euros(apres)}",
            empreinte: [etat(stay), id, paiement.updated_at.to_f, changements.transform_values(&:to_s)],
            donnees: { stay_id: stay.id, id: id, changements: changements }
          )
        end

        def appliquer(plan)
          stay = Stay.find(plan.donnees[:stay_id])
          appliquer_sur(stay, plan.donnees[:id], plan.donnees[:changements])
          "Paiement ##{plan.donnees[:id]} mis à jour. Reste dû : #{euros(stay.reload.balance_due_cents)}."
        end

        def appliquer_sur(stay, id, changements)
          stay.direct_payments.find(id).update!(changements)
          stay.set_payment_status
        end
      end
    end
  end
end
