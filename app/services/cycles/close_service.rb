module Cycles
  # Clôture d'un cycle : tout ce qui est encore en jeu reçoit une issue, les
  # rituelles et les reportées repartent dans le cycle suivant, le cycle est
  # verrouillé. Les décisions individuelles ont été prises sur la page de
  # clôture avant l'appel ; ici on applique les règles par défaut à ce qui
  # reste :
  #   - cochée            → faite (+ recréée si rituelle)
  #   - rituelle non faite → reportée + recréée
  #   - catégorie reportée → reportée + recréée (ponctuelle)
  #   - autre non cochée   → abandonnée
  class CloseService < ServiceBase
    attr_reader :cycle, :summary

    NO_NEXT_CYCLE = CycleActions::DeferService::NO_NEXT_CYCLE

    def initialize(cycle:)
      @cycle = cycle
      @report_errors = false
      @summary = Hash.new(0)
    end

    def run
      catch_error(context: { cycle_id: cycle.id }) { run! }
    end

    def run!
      raise ServiceError, "Ce cycle est déjà clos." if cycle.closed?
      next_cycle = cycle.next_cycle
      raise ServiceError, NO_NEXT_CYCLE unless next_cycle

      Cycle.transaction do
        cycle.cycle_actions.live.find_each do |action|
          settle(action, next_cycle)
        end
        cycle.update!(closed_at: Time.current)
      end
      true
    end

    private

    def settle(action, next_cycle)
      if action.completed?
        action.update!(outcome: :done)
        recreate(action, next_cycle, count: action.deferral_count) if action.rituelle?
        summary[:done] += 1
      elsif action.rituelle? || action.reportee?
        action.update!(outcome: :deferred)
        recreate(action, next_cycle, count: action.deferral_count.to_i + (action.rituelle? ? 0 : 1))
        summary[:deferred] += 1
      else
        action.update!(outcome: :dropped)
        summary[:dropped] += 1
      end
    end

    def recreate(action, next_cycle, count:)
      CycleAction.create!(
        cycle: next_cycle,
        human: action.human,
        delegate_to_human: action.delegate_to_human,
        label: action.label,
        hours: action.hours,
        category: action.reportee? ? "ponctuelle" : action.category,
        completed: false,
        deferred_from: action,
        deferral_count: count
      )
    end
  end
end
