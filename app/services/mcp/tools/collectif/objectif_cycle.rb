module Mcp
  module Tools
    module Collectif
      # Les objectifs d'un membre pour un cycle (CycleTargetsController).
      class ObjectifCycle < Ecriture
        include Commun

        GESTES = %w[ajouter atteint pas_atteint supprimer].freeze

        tool "objectif_cycle",
             title: "Objectif de cycle d'un membre",
             description: "Ajoute un objectif (une intention, sans heures) à un membre pour un cycle, le marque " \
                          "atteint ou non, ou le supprime. Un cycle clos ne se modifie plus.",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES },
                 objectif: { type: %w[integer string], description: "Identifiant (#7), rendu par actions_membre." },
                 membre: MEMBRE.merge(description: "Pour ajouter (défaut : moi)."),
                 cycle: CYCLE,
                 libelle: { type: "string" }
               },
               required: %w[geste]
             }

        private

        def planifier(arguments)
          geste = arguments["geste"].to_s
          raise Error, "geste : #{GESTES.join(', ')}." unless GESTES.include?(geste)

          if geste == "ajouter"
            libelle = arguments["libelle"].to_s.strip
            raise Error, "Donne le libellé de l'objectif." if libelle.empty?

            cycle = cycle!(arguments["cycle"])
            ouvert!(cycle)
            membre = arguments["membre"].present? ? membre!(arguments["membre"]) : moi!
            return Plan.new(resume: "Objectif pour #{membre.name}, cycle « #{cycle.name} » : « #{libelle} »",
                            empreinte: [membre.id, cycle.id, libelle],
                            donnees: { geste: geste, human_id: membre.id, cycle_id: cycle.id, label: libelle })
          end

          objectif = CycleTarget.includes(:human, :cycle).find_by(id: id!(arguments["objectif"], "objectif")) ||
                     raise(Error, "Aucun objectif ##{arguments['objectif']}.")
          ouvert!(objectif.cycle)
          raise Error, "Il est déjà atteint." if geste == "atteint" && objectif.achieved?
          raise Error, "Il n'est pas marqué atteint." if geste == "pas_atteint" && !objectif.achieved?

          sens = { "atteint" => "Marquer ATTEINT", "pas_atteint" => "Marquer non atteint", "supprimer" => "SUPPRIMER" }[geste]
          Plan.new(resume: "#{sens} : objectif ##{objectif.id} de #{objectif.human&.name} « #{objectif.label} »",
                   empreinte: [etat_de(objectif), geste], donnees: { geste: geste, id: objectif.id })
        end

        def appliquer(plan)
          d = plan.donnees
          case d[:geste]
          when "ajouter"
            objectif = CycleTarget.create!(human_id: d[:human_id], cycle_id: d[:cycle_id], label: d[:label])
            "Objectif ##{objectif.id} ajouté."
          when "supprimer"
            CycleTarget.find(d[:id]).destroy!
            "Objectif ##{d[:id]} supprimé."
          else
            objectif = CycleTarget.find(d[:id])
            objectif.toggle_achieved!
            "Objectif ##{objectif.id} #{objectif.achieved? ? 'atteint' : 'rouvert'}."
          end
        end
      end
    end
  end
end
