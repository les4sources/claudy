module Mcp
  module Tools
    module Cuisine
      # Le formulaire « Modifier » d'une ligne de la page Cuisine
      # (Kitchen::OrdersController#update), hors statut et responsable qui ont
      # leurs propres outils.
      class ModifierPrestation < Ecriture
        include Commun

        tool "modifier_prestation",
             title: "Modifier une prestation de cuisine",
             description: "Change le type, la date, le moment, le nombre de convives, le prix par personne, les " \
                          "précisions, l'origine ou le « pour qui » d'une prestation. Changer type, date, moment ou " \
                          "convives d'une prestation acceptée la REMET EN ATTENTE de la cuisine, qui reçoit un email.",
             schema: {
               properties: {
                 prestation: PRESTATION,
                 type: TYPE,
                 date: DATE,
                 moment: MOMENT,
                 convives: { type: "integer", minimum: 1 },
                 prix_par_personne: { type: %w[number string],
                                      description: "Prix imposé par personne en euros ; « aucun » revient au barème." },
                 precisions: { type: "string", description: "Remplace les précisions (allergies, régimes, consignes)." },
                 origine: { type: "string", enum: MealOrder::ORIGINS },
                 pour_qui: { type: "string", description: "Le « pour qui » d'une demande sans séjour." }
               },
               required: %w[prestation]
             }

        # Après le commit : la remise trio se recalcule en `after_commit`, le
        # total du séjour doit la voir.
        def self.transactionnel? = false

        private

        def planifier(arguments)
          order = prestation!(arguments["prestation"])
          raise Error, "Prestation passée : elle ne se modifie plus." if order.past?

          attributs = attributs(order, arguments)
          raise Error, "Rien à changer : donne au moins un champ." if attributs.empty?

          apres = simuler do
            copie = MealOrder.find(order.id)
            copie.assign_attributes(attributs)
            copie.save!
            [ligne_prestation(copie), copie.pending? && order.accepted?, copie.warnings]
          rescue ActiveRecord::RecordInvalid => e
            raise Error, e.record.errors.full_messages.to_sentence
          end
          ligne, revalider, alertes = apres

          resume = ["Avant : #{ligne_prestation(order)}", "Après : #{ligne}"]
          resume.concat(alertes.map { |a| "⚠ #{a}." })
          email = destinataire_cuisine(order)
          resume << if revalider && order.family == "repas"
                      "La cuisine avait accepté : elle devra REVALIDER. Email à #{email || 'personne (pas de responsable)'}."
                    elsif revalider
                      "La personne qui s'en charge est prévenue du changement par email (#{email || 'personne'})."
                    else
                      "Pas de nouvel accord à demander à la cuisine."
                    end
          resume << "Le total du séjour ##{order.stay_id} sera recalculé." if order.stay_id

          Plan.new(resume: resume.join("\n"), empreinte: [etat_prestation(order), attributs.transform_values(&:to_s).sort],
                   donnees: { id: order.id, attributs: attributs })
        end

        def appliquer(plan)
          order = prestation!(plan.donnees[:id])
          order.update!(plan.donnees[:attributs])
          recalculer!(order.stay)
          "Prestation modifiée : #{ligne_prestation(order.reload)}"
        rescue ActiveRecord::RecordInvalid => e
          raise Error, e.record.errors.full_messages.to_sentence
        end

        def attributs(order, arguments)
          attrs = {}
          attrs[:kind] = type!(arguments["type"], actuel: order.kind) if arguments["type"].present?
          attrs[:date] = date!(arguments["date"], "date") if arguments["date"].present?
          attrs[:moment] = moment!(arguments["moment"]) if arguments["moment"].present?
          attrs[:people] = convives!(arguments["convives"]) if arguments.key?("convives")
          if arguments.key?("prix_par_personne")
            prix = prix_unitaire(arguments["prix_par_personne"])
            attrs[:unit_price_cents] = prix == :effacer ? nil : prix
          end
          attrs[:notes] = arguments["precisions"].to_s.strip if arguments.key?("precisions")
          attrs[:origin] = arguments["origine"] if arguments["origine"].present?
          if arguments.key?("pour_qui")
            attrs[:contact_label] = arguments["pour_qui"].to_s.strip.presence
          end
          if attrs[:date] && attrs[:date] < Date.current
            raise Error, "Une prestation ne se déplace pas dans le passé."
          end

          attrs.reject { |cle, valeur| order.public_send(cle) == valeur }
        end
      end
    end
  end
end
