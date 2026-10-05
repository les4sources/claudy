module Mcp
  module Tools
    module Collectif
      # La page d'un membre dans « Cycles » (OrganisationController#member) :
      # ses actions par catégorie, ses objectifs, ce qu'on lui demande.
      class ActionsMembre < Base
        include Commun

        tool "actions_membre",
             title: "Actions de cycle d'un membre",
             description: "Les actions d'un membre sur un cycle (défaut : le cycle de référence), par catégorie " \
                          "(rituelle, ponctuelle, reportée, déléguée, demandée, invitée) avec heures, occurrences, " \
                          "heures réelles ; ses objectifs ; les actions tranchées ; les demandes des autres membres ; " \
                          "ses actions de rassemblement. Avec `archives`, ses actions archivées.",
             schema: {
               properties: {
                 membre: MEMBRE, cycle: CYCLE,
                 archives: { type: "boolean", description: "Lister plutôt les actions archivées (tous cycles)." }
               },
               required: %w[membre]
             }

        def call(arguments)
          membre = membre!(arguments["membre"])
          return archives(membre) if arguments["archives"]

          cycle = cycle!(arguments["cycle"])
          actions = membre.cycle_actions.for_cycle(cycle).includes(:team).to_a
          vivantes = actions.select(&:live?).sort_by { |a| [a.completed? ? 1 : 0, a.position.to_i, a.created_at] }
          engage = vivantes.reject { |a| a.completed? || a.reportee? || a.economic? }.sum { |a| a.hours.to_f }

          blocs = ["#{membre.name} · cycle ##{cycle.id} « #{cycle.name} »#{' (clos)' if cycle.closed?} · " \
                   "#{heures(engage)} encore engagées (hors économique et reportées)"]
          CATEGORIES.each do |categorie, label|
            dans = vivantes.select { |a| a.category == categorie }
            blocs << "#{label} :\n#{dans.map { |a| "- #{ligne_action_cycle(a)}" }.join("\n")}" if dans.any?
          end
          blocs << "Aucune action en cours." if vivantes.empty?
          objectifs = membre.cycle_targets.for_cycle(cycle).ordered.to_a
          if objectifs.any?
            blocs << "Objectifs :\n#{objectifs.map { |o| "- Objectif ##{o.id} #{o.achieved? ? '[atteint] ' : ''}#{o.label}" }.join("\n")}"
          end
          tranchees = actions.reject(&:live?).reject { |a| cycle.open? && a.archived? }
          blocs << "Tranchées :\n#{tranchees.map { |a| "- #{ligne_action_cycle(a)}" }.join("\n")}" if tranchees.any?
          demandees = CycleAction.for_cycle(cycle).demandee.live.active.where.not(human_id: membre.id).includes(:human)
          if demandees.any?
            blocs << "Demandées par d'autres :\n#{demandees.map { |a| "- #{a.human.name} : #{ligne_action_cycle(a)}" }.join("\n")}"
          end
          rassemblement = membre.gathering_actions.includes(:gathering).where(completed: false).order(created_at: :desc).limit(20)
          if rassemblement.any?
            blocs << "Actions de rassemblement à faire :\n" \
                     "#{rassemblement.map { |a| "- Action ##{a.id} #{a.label} (rassemblement ##{a.gathering_id})" }.join("\n")}"
          end
          blocs.join("\n\n")
        end

        private

        def archives(membre)
          liste = membre.cycle_actions.archived.includes(:cycle, :team).order(archived_at: :desc).limit(80).to_a
          return "#{membre.name} n'a aucune action archivée." if liste.empty?

          "Archives de #{membre.name} :\n#{liste.map { |a| "- #{a.cycle&.name} · #{ligne_action_cycle(a)}" }.join("\n")}"
        end
      end
    end
  end
end
