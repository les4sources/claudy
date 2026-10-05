module Mcp
  module Tools
    module Cuisine
      # « Je m'en charge » / « Confier à » (Kitchen::OrdersController#assign).
      class ConfierPrestation < Ecriture
        include Commun

        tool "confier_prestation",
             title: "Confier une prestation à un membre",
             description: "Désigne qui prépare une prestation (« moi » pour le compte connecté). Pour un buffet ou un " \
                          "apéro, se charger VAUT ACCEPTATION ; un repas garde la validation de la cuisine.",
             schema: { properties: { prestation: PRESTATION, responsable: MEMBRE }, required: %w[prestation responsable] }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          order = prestation!(arguments["prestation"])
          raise Error, "Prestation annulée : on ne la confie plus." if order.cancelled?
          raise Error, "Prestation passée : on ne la confie plus." if order.past?

          membre = membre!(arguments["responsable"])
          raise Error, "#{membre.name} s'en charge déjà." if order.responsible_human_id == membre.id

          accepte = order.family != "repas" && !order.refused? && !order.accepted?
          resume = [ligne_prestation(order), "Responsable : #{order.responsible_human&.name || 'personne'} → #{membre.name}"]
          resume << "Se charger d'un #{order.family_label.downcase} vaut acceptation : la prestation sera acceptée." if accepte
          resume << "La cuisine l'a refusée : elle reste refusée tant que personne ne l'accepte (repondre_prestation)." if order.refused?
          resume << "Aucun email."
          Plan.new(resume: resume.join("\n"), empreinte: [etat_prestation(order), membre.id],
                   donnees: { id: order.id, membre_id: membre.id, accepte: accepte })
        end

        def appliquer(plan)
          order = prestation!(plan.donnees[:id])
          order.responsible_human = Human.find(plan.donnees[:membre_id])
          order.assign_attributes(validation: "accepted", validated_at: Time.current) if plan.donnees[:accepte]
          order.save!
          "#{order.responsible_human.name} s'en charge : #{ligne_prestation(order.reload)}"
        end
      end
    end
  end
end
