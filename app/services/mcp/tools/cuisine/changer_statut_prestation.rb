module Mcp
  module Tools
    module Cuisine
      # Le menu de statut client d'une ligne (Kitchen::OrdersController#status) :
      # demande d'info, demande ferme, confirmé, annulé (motif obligatoire).
      class ChangerStatutPrestation < Ecriture
        include Commun

        tool "changer_statut_prestation",
             title: "Changer le statut client d'une prestation",
             description: "Passe une prestation en demande d'info (inquiry, non facturée), demande ferme (requested), " \
                          "confirmée (confirmed) ou annulée (cancelled, avec raison). Confirmer ou annuler envoie un " \
                          "EMAIL AU RESPONSABLE de la cuisine (jamais au client). Le total du séjour suit.",
             schema: {
               properties: {
                 prestation: PRESTATION,
                 statut: STATUT,
                 raison: { type: "string", description: "Obligatoire pour annuler : pourquoi (inscrit sur la ligne, lu par la cuisine)." }
               },
               required: %w[prestation statut]
             }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          order = prestation!(arguments["prestation"])
          statut = arguments["statut"].to_s
          raise Error, "statut : #{MealOrder::STATUSES.join(', ')}." unless MealOrder::STATUSES.include?(statut)
          raise Error, "La prestation est déjà « #{order.status_label} »." if order.status == statut

          raison = arguments["raison"].to_s.strip
          raise Error, "Un motif est nécessaire pour annuler une demande (raison)." if statut == "cancelled" && raison.empty?

          attributs = { status: statut }
          attributs[:cancellation_reason] = raison if statut == "cancelled"

          resume = [ligne_prestation(order), "Statut : #{order.status_label} → #{MealOrder::STATUS_LABELS[statut]}"]
          resume << "Raison : #{raison}" if statut == "cancelled"
          resume << email(order, statut)
          if order.stay_id
            facturable = MealOrder.new(stay_id: order.stay_id, status: statut, validation: order.validation).billable?
            resume << "Facturée au séjour ##{order.stay_id} : #{order.billable? ? 'oui' : 'non'} → #{facturable ? 'oui' : 'non'} (total recalculé)."
          end
          Plan.new(resume: resume.join("\n"), empreinte: [etat_prestation(order), attributs.to_a],
                   donnees: { id: order.id, attributs: attributs })
        end

        def appliquer(plan)
          order = prestation!(plan.donnees[:id])
          order.update!(plan.donnees[:attributs])
          recalculer!(order.stay)
          "Statut changé : #{ligne_prestation(order.reload)}"
        rescue ActiveRecord::RecordInvalid => e
          raise Error, e.record.errors.full_messages.to_sentence
        end

        # Ce que fera Kitchen::Notifier au commit.
        def email(order, statut)
          return "Prestation passée : aucun email." if order.past?

          destinataire = destinataire_cuisine(order) || "personne (pas de responsable)"
          case statut
          when "cancelled" then "Email d'annulation à #{destinataire}."
          when "confirmed" then "Email de confirmation à #{destinataire}."
          else "Aucun email."
          end
        end
      end
    end
  end
end
