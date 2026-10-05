module Mcp
  module Tools
    module Cuisine
      # La réponse de la cuisine : « Ok ! », « Pas possible » ou « Se désister »
      # (Kitchen::OrdersController#accept et #refuse).
      class RepondrePrestation < Ecriture
        include Commun

        tool "repondre_prestation",
             title: "Réponse de la cuisine à une prestation",
             description: "La cuisine accepte une prestation en attente, ou la refuse (pas possible, ou désistement " \
                          "d'une prestation déjà acceptée) avec une raison. Un refus envoie un EMAIL À LA COORDINATION " \
                          "(l'accueil cherche une solution) ; une acceptation n'envoie rien.",
             schema: {
               properties: {
                 prestation: PRESTATION,
                 decision: { type: "string", enum: %w[accepter refuser] },
                 raison: { type: "string", description: "Obligatoire pour refuser : pourquoi la cuisine ne peut pas." }
               },
               required: %w[prestation decision]
             }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          order = prestation!(arguments["prestation"])
          raise Error, "Prestation annulée par le client : plus rien à répondre." if order.cancelled?
          raise Error, "Prestation passée : la réponse ne se change plus." if order.past?

          raison = arguments["raison"].to_s.strip
          resume = [ligne_prestation(order)]
          case arguments["decision"]
          when "accepter"
            raise Error, "La cuisine a déjà accepté cette prestation." if order.accepted?
            raise Error, "La cuisine l'a refusée : pour la reprendre, confie-la (confier_prestation) ou modifie-la." if order.refused?

            resume << "La cuisine ACCEPTE. Aucun email."
          when "refuser"
            raise Error, "La cuisine l'a déjà refusée." if order.refused?
            raise Error, "Un motif est nécessaire pour refuser (raison)." if raison.empty?

            resume << "La cuisine #{order.accepted? ? 'SE DÉSISTE' : 'REFUSE'} : « #{raison} »."
            resume << "Email à la coordination (#{Kitchen::Config.coordinator_email}) ; la prestation passe « à couvrir »."
          else
            raise Error, "decision : accepter ou refuser."
          end
          Plan.new(resume: resume.join("\n"), empreinte: [etat_prestation(order), order.validation, arguments["decision"], raison],
                   donnees: { id: order.id, decision: arguments["decision"], raison: raison })
        end

        def appliquer(plan)
          order = prestation!(plan.donnees[:id])
          plan.donnees[:decision] == "accepter" ? order.accept! : order.refuse!(plan.donnees[:raison])
          recalculer!(order.stay)
          "Réponse enregistrée : #{ligne_prestation(order.reload)}"
        end
      end
    end
  end
end
