module Mcp
  module Tools
    module Collectif
      # La vue d'ensemble « Cycles » (OrganisationController#index) : la charge
      # de chaque membre sur le cycle, le bilan, les cycles.
      class CycleCollectif < Base
        include Commun

        CHARGES = { overload: "SURCHARGÉ", tight: "tendu", idle: "peu engagé", ok: "ok" }.freeze

        tool "cycle_collectif",
             title: "Cycle du collectif",
             description: "Vue d'ensemble d'un cycle (défaut : le cycle de référence) : par membre actif en cycle, " \
                          "heures engagées et restantes, charge face à la capacité (16 h par semaine), heures faites, " \
                          "objectifs ; plus la liste des cycles, le prochain rassemblement et les dernières décisions.",
             schema: { properties: { cycle: CYCLE } }

        def call(arguments)
          cycle = cycle!(arguments["cycle"])
          membres = Human.cycle_active.roles_enabled.order(:name).to_a
          rapports = Cycles::MemberReport.for_cycle(cycle, humans: membres)
          charge = Object.new.extend(CycleLoadHelper)

          lignes = rapports.map do |rapport|
            restant = rapport.live_actions.reject { |a| a.completed? || a.reportee? || a.economic? }.sum { |a| a.hours.to_f }
            load = charge.cycle_load_for(engaged: restant, cycle: cycle)
            objectifs = rapport.targets
            "- #{rapport.human.name} : #{heures(restant)} encore engagées (#{load[:pct]} % de #{heures(load[:available])}, " \
              "#{CHARGES.fetch(load[:state], load[:state])}) · prévu #{heures(rapport.planned_hours)}, fait #{heures(rapport.done_hours)}" \
              "#{" · objectifs #{rapport.targets_achieved.size}/#{objectifs.size}" if objectifs.any?}"
          end
          [entete(cycle), "Membres :\n#{lignes.join("\n").presence || '(aucun membre actif en cycle)'}", autour].join("\n\n")
        end

        private

        def entete(cycle)
          etat = cycle.closed? ? "clos le #{I18n.l(cycle.closed_at.to_date)}" : "ouvert"
          "Cycle ##{cycle.id} « #{cycle.name} » du #{cycle.start_date} au #{cycle.end_date} (#{etat})\n" \
            "Cycles : #{Cycle.chronological.limit(6).map { |c| "##{c.id} #{c.name}#{' (clos)' if c.closed?}" }.join(', ')}"
        end

        def autour
          prochain = Gathering.upcoming.includes(:gathering_category, :teams).first
          decisions = Decision.recent.limit(4).map { |d| "- #{ligne_decision(d)}" }
          "Prochain rassemblement : #{prochain ? ligne_rassemblement(prochain) : 'aucun'}\n" \
            "Dernières décisions :\n#{decisions.join("\n").presence || '(aucune)'}"
        end
      end
    end
  end
end
