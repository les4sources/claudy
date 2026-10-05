module Mcp
  module Tools
    module Collectif
      # Le formulaire d'une action de cycle (CycleActionsController : create, update).
      class EnregistrerActionCycle < Ecriture
        include Commun

        tool "enregistrer_action_cycle",
             title: "Créer ou modifier une action de cycle",
             description: "Sans `action` : crée une action pour un membre dans un cycle (défaut : le cycle de " \
                          "référence) — libellé, catégorie (rituelle, ponctuelle, reportée, déléguée, demandée, invitée), " \
                          "durée par fois et nombre de fois, pôle, activité économique. Avec : modifie ce qui est donné. " \
                          "Un cycle clos ne se modifie plus.",
             schema: {
               properties: {
                 action: ACTION_CYCLE,
                 membre: MEMBRE.merge(description: "À qui est l'action (à la création ; « moi » par défaut)."),
                 cycle: CYCLE,
                 libelle: { type: "string" },
                 categorie: { type: "string", enum: CycleAction.categories.keys },
                 heures_par_fois: { type: %w[number string], description: "Durée d'une fois, en heures (ex. 1,5)." },
                 fois: { type: "integer", minimum: 1, description: "Nombre de fois dans le cycle (défaut 1)." },
                 pole: { type: "string", description: "Pôle (nom) ; « aucun » pour retirer." },
                 economique: { type: "boolean", description: "Activité qui rapporte : hors budget d'heures du cycle." }
               }
             }

        private

        def planifier(arguments)
          action = arguments["action"].present? ? action_cycle!(arguments["action"]) : nil
          attributs = attributs(arguments)
          if action
            ouvert!(action.cycle)
            raise Error, "Rien à changer." if attributs.empty?
          else
            raise Error, "Donne le libellé de l'action." if attributs[:label].blank?

            cycle = cycle!(arguments["cycle"])
            ouvert!(cycle)
            attributs[:cycle_id] = cycle.id
            attributs[:human_id] = (arguments["membre"].present? ? membre!(arguments["membre"]) : moi!).id
            attributs[:category] ||= "ponctuelle"
          end

          apres = simuler { enregistrer(action && CycleAction.find(action.id), attributs) }
          resume = [action && "Avant : #{ligne_action_cycle(action)}", "#{action ? 'Après' : 'Créer'} : #{apres}"]
          resume << "Pour #{Human.find(attributs[:human_id]).name}, cycle « #{Cycle.find(attributs[:cycle_id]).name} »." unless action
          Plan.new(resume: resume.compact.join("\n"), empreinte: [action && etat_de(action), signature(arguments)],
                   donnees: { id: action&.id, attributs: attributs })
        end

        def appliquer(plan)
          id = plan.donnees[:id]
          "Action enregistrée : #{enregistrer(id && CycleAction.find(id), plan.donnees[:attributs])}"
        end

        def enregistrer(action, attributs)
          params = ActionController::Parameters.new(cycle_action: attributs)
          service = action ? CycleActions::UpdateService.new(cycle_action: action) : CycleActions::CreateService.new
          service! { service.run!(params) }
          ligne_action_cycle(CycleAction.includes(:team).find(service.cycle_action.id))
        rescue ActiveRecord::RecordInvalid => e
          raise Error, e.record.errors.full_messages.to_sentence
        end

        def attributs(arguments)
          attributs = {}
          attributs[:label] = arguments["libelle"].to_s.strip if arguments["libelle"].present?
          if arguments["categorie"].present?
            raise Error, "categorie : #{CycleAction.categories.keys.join(', ')}." unless CycleAction.categories.key?(arguments["categorie"])

            attributs[:category] = arguments["categorie"]
          end
          if arguments.key?("heures_par_fois")
            texte = arguments["heures_par_fois"].to_s.strip.tr(",", ".")
            raise Error, "heures_par_fois : un nombre d'heures (ex. 1,5)." unless texte.match?(/\A\d+(\.\d+)?\z/)

            attributs[:unit_hours] = texte
          end
          attributs[:occurrences] = Integer(arguments["fois"].to_s) if arguments["fois"].present?
          if arguments.key?("pole")
            attributs[:team_id] = arguments["pole"].to_s.strip.match?(/\A(|aucun)\z/i) ? nil : pole!(arguments["pole"]).id
          end
          attributs[:economic] = arguments["economique"] ? true : false if arguments.key?("economique")
          attributs
        rescue ArgumentError
          raise Error, "fois : un nombre entier."
        end
      end
    end
  end
end
