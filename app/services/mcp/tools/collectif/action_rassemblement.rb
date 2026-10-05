module Mcp
  module Tools
    module Collectif
      # Les actions décidées en rassemblement (GatheringActionsController).
      class ActionRassemblement < Ecriture
        include Commun

        GESTES = %w[ajouter modifier cocher decocher supprimer].freeze

        tool "action_rassemblement",
             title: "Action décidée en rassemblement",
             description: "Ajoute une action à un rassemblement (libellé, qui la porte), la modifie, la coche faite " \
                          "ou la décoche, ou la supprime.",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES },
                 rassemblement: RASSEMBLEMENT.merge(description: "Pour ajouter."),
                 action: { type: %w[integer string], description: "Identifiant de l'action (#14), rendu par fiche_rassemblement." },
                 libelle: { type: "string" },
                 porteurs: { type: "array", items: { type: "string" }, description: "Membres qui la portent (noms, « moi ») ; remplace la liste." }
               },
               required: %w[geste]
             }

        private

        def planifier(arguments)
          geste = arguments["geste"].to_s
          raise Error, "geste : #{GESTES.join(', ')}." unless GESTES.include?(geste)

          porteurs = arguments.key?("porteurs") ? Array(arguments["porteurs"]).map { |nom| membre!(nom) } : nil
          if geste == "ajouter"
            gathering = rassemblement!(arguments["rassemblement"].presence || raise(Error, "Donne le rassemblement."))
            libelle = arguments["libelle"].to_s.strip
            raise Error, "Donne le libellé de l'action." if libelle.empty?

            return Plan.new(resume: "Ajouter à #{ligne_rassemblement(gathering)}\nAction « #{libelle} »#{" → #{porteurs.map(&:name).join(', ')}" if porteurs&.any?}",
                            empreinte: [etat_de(gathering), signature(arguments)],
                            donnees: { geste: geste, rassemblement: gathering.id, label: libelle, human_ids: porteurs&.map(&:id) })
          end

          action = GatheringAction.includes(:assignees).find_by(id: id!(arguments["action"], "action")) ||
                   raise(Error, "Aucune action de rassemblement ##{arguments['action']}.")
          resume = case geste
                   when "modifier"
                     raise Error, "Rien à changer : libelle ou porteurs." if arguments["libelle"].blank? && porteurs.nil?

                     ["Modifier", arguments["libelle"].present? && "libellé → « #{arguments['libelle'].strip} »",
                      porteurs && "porteurs → #{porteurs.map(&:name).join(', ').presence || 'personne'}"].select(&:itself).join(" · ")
                   when "cocher" then action.completed? ? raise(Error, "Déjà faite.") : "Cocher : faite."
                   when "decocher" then action.completed? ? "Décocher : à faire." : raise(Error, "Elle n'est pas cochée.")
                   when "supprimer" then motif!({ "motif" => @motif }) && "SUPPRIMER cette action."
                   end
          Plan.new(resume: "#{ligne_action(action)}\n#{resume}", empreinte: [etat_de(action), signature(arguments)],
                   donnees: { geste: geste, id: action.id, label: arguments["libelle"].to_s.strip.presence, human_ids: porteurs&.map(&:id) })
        end

        def appliquer(plan)
          d = plan.donnees
          params = { label: d[:label] }.compact
          params[:human_ids] = d[:human_ids].map(&:to_s) unless d[:human_ids].nil?
          case d[:geste]
          when "ajouter"
            service = GatheringActions::CreateService.new(gathering: Gathering.find(d[:rassemblement]))
            service! { service.run!(ActionController::Parameters.new(gathering_action: params)) }
            "Action ajoutée : #{ligne_action(service.gathering_action)}"
          when "modifier"
            action = GatheringAction.find(d[:id])
            service! { GatheringActions::UpdateService.new(gathering_action: action).run!(ActionController::Parameters.new(gathering_action: params)) }
            "Action modifiée : #{ligne_action(action.reload)}"
          when "cocher", "decocher"
            action = GatheringAction.find(d[:id])
            action.toggle_completed!
            "Action #{action.completed? ? 'faite' : 'rouverte'} : #{ligne_action(action)}"
          when "supprimer"
            GatheringAction.find(d[:id]).soft_delete!(validate: false)
            "Action ##{d[:id]} supprimée (suppression douce)."
          end
        end

        def ligne_action(action)
          "Action ##{action.id} #{action.completed? ? '[faite] ' : ''}« #{action.label} »" \
            "#{" → #{action.assignees.map(&:name).join(', ')}" if action.assignees.any?} · rassemblement ##{action.gathering_id}"
        end
      end
    end
  end
end
