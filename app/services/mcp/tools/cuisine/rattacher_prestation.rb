module Mcp
  module Tools
    module Cuisine
      # « Rattacher à un séjour » d'une demande prise sans séjour
      # (Kitchen::OrdersController#attach).
      class RattacherPrestation < Ecriture
        include Commun
        include Sejours::Commun

        tool "rattacher_prestation",
             title: "Rattacher une prestation à un séjour",
             description: "Rattache une demande de cuisine prise sans séjour (« pour qui ») au séjour enregistré " \
                          "depuis. Elle entre alors dans le total du séjour. Une prestation déjà rattachée ne change pas de séjour.",
             schema: { properties: { prestation: PRESTATION, sejour: SEJOUR }, required: %w[prestation sejour] }

        def self.transactionnel? = false

        private

        def planifier(arguments)
          order = prestation!(arguments["prestation"])
          raise Error, "Cette prestation est déjà rattachée au séjour ##{order.stay_id}." if order.stay_id

          stay = sejour!(arguments["sejour"])
          resume = [ligne_prestation(order), "→ séjour #{ligne_sejour(stay)}"]
          facturable = %w[requested confirmed].include?(order.status) && !order.refused?
          resume << if facturable
                      "Elle sera facturée : #{euros(order.price_cents)} ajoutés au total du séjour."
                    else
                      "Elle ne sera pas facturée (#{order.status_label.downcase}, cuisine : #{order.validation_label.downcase})."
                    end
          Plan.new(resume: resume.join("\n"), empreinte: [etat_prestation(order), etat(stay)],
                   donnees: { id: order.id, stay_id: stay.id })
        end

        def appliquer(plan)
          order = prestation!(plan.donnees[:id])
          stay = Stay.find(plan.donnees[:stay_id])
          raise Error, "Elle vient d'être rattachée ailleurs : rien n'a été fait." unless order.attach_to_stay!(stay)

          recalculer!(stay)
          "Prestation rattachée : #{ligne_prestation(order.reload)}"
        end
      end
    end
  end
end
