module CycleActions
  # Passe une action au cycle suivant : l'origine garde sa place dans le bilan
  # de son cycle avec l'issue « reportée », et une copie liée démarre dans le
  # cycle suivant. Sans cycle suivant configuré, refuse avec un message clair.
  class DeferService < ServiceBase
    attr_reader :cycle_action, :copy, :target_cycle

    NO_NEXT_CYCLE = "Aucun cycle suivant n'est configuré : créez-le d'abord.".freeze
    CLOSED = "Ce cycle est clos.".freeze

    def initialize(cycle_action:)
      @cycle_action = cycle_action
      @report_errors = false
    end

    def run
      catch_error(context: { cycle_action_id: cycle_action.id }) { run! }
    end

    def run!
      raise ServiceError, CLOSED if cycle_action.cycle.closed?
      @target_cycle = cycle_action.cycle.next_cycle
      raise ServiceError, NO_NEXT_CYCLE unless target_cycle
      raise ServiceError, "Cette action a déjà été tranchée." unless cycle_action.live?

      CycleAction.transaction do
        @copy = CycleAction.create!(
          cycle: target_cycle,
          human: cycle_action.human,
          delegate_to_human: cycle_action.delegate_to_human,
          label: cycle_action.label,
          hours: cycle_action.hours,
          category: copy_category,
          completed: false,
          deferred_from: cycle_action,
          deferral_count: cycle_action.deferral_count.to_i + 1
        )
        cycle_action.update!(outcome: :deferred)
      end
      true
    end

    private

    # Une action mise dans le sas « reportée » redevient ponctuelle dans le
    # cycle suivant : c'est là qu'elle doit être faite.
    def copy_category
      cycle_action.reportee? ? "ponctuelle" : cycle_action.category
    end
  end
end
