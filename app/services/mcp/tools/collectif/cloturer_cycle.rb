module Mcp
  module Tools
    module Collectif
      # La clôture d'un cycle (CyclesController#closing et #close).
      class CloturerCycle < Ecriture
        include Commun

        tool "cloturer_cycle",
             title: "Clôturer un cycle",
             description: "Clôt un cycle : chaque action encore en jeu reçoit une issue (cochée → faite, et une rituelle " \
                          "repart au cycle suivant ; rituelle ou reportée non faite → passée au cycle suivant ; le reste " \
                          "→ abandonné) et le cycle est verrouillé. L'aperçu donne le compte et la liste de ce qui reste à " \
                          "trancher : on peut d'abord trancher action par action avec geste_action_cycle.",
             schema: { properties: { cycle: CYCLE }, required: %w[cycle] }

        private

        def planifier(arguments)
          cycle = cycle!(arguments["cycle"])
          ouvert!(cycle)
          suivant = cycle.next_cycle
          raise Error, CycleActions::DeferService::NO_NEXT_CYCLE unless suivant

          en_jeu = cycle.cycle_actions.live.includes(:human, :team).order(:human_id, :category).to_a
          bilan = simuler do
            service = Cycles::CloseService.new(cycle: cycle.class.find(cycle.id))
            service! { service.run! }
            service.summary.dup
          end
          lignes = en_jeu.map { |a| "- #{a.human&.name} : #{ligne_action_cycle(a)} → #{issue(a)}" }
          resume = "Clore le cycle ##{cycle.id} « #{cycle.name} » (#{cycle.start_date} → #{cycle.end_date}). " \
                   "Cycle suivant : « #{suivant.name} ».\n" \
                   "#{bilan[:done]} faite(s), #{bilan[:deferred]} passée(s) au suivant, #{bilan[:dropped]} abandonnée(s).\n" \
                   "#{lignes.join("\n")}"
          Plan.new(resume: resume, empreinte: [etat_de(cycle), en_jeu.map { |a| etat_de(a) }], donnees: { id: cycle.id })
        end

        def appliquer(plan)
          service = Cycles::CloseService.new(cycle: Cycle.find(plan.donnees[:id]))
          service! { service.run! }
          s = service.summary
          "Cycle clos : #{s[:done]} faite(s), #{s[:deferred]} passée(s) au suivant, #{s[:dropped]} abandonnée(s)."
        end

        def issue(action)
          return action.rituelle? ? "faite, et recréée au suivant" : "faite" if action.completed?
          return "passée au suivant" if action.rituelle? || action.reportee?

          "abandonnée"
        end
      end
    end
  end
end
