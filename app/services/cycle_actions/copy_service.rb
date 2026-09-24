module CycleActions
  # Copie une action au cycle suivant sans la faire quitter le sien (epic #330,
  # phase 4) : là où `DeferService` DÉPLACE (l'origine prend l'issue
  # « reportée »), celui-ci DUPLIQUE — l'origine ne bouge pas.
  #
  # Idempotent (décision 6) : tant qu'une copie vivante existe, un nouvel appel
  # la retire (soft-delete) au lieu d'en créer une deuxième. `copied?` dit dans
  # quel sens on est allé.
  class CopyService < ServiceBase
    attr_reader :cycle_action, :copy, :target_cycle

    NO_NEXT_CYCLE = DeferService::NO_NEXT_CYCLE
    CLOSED = DeferService::CLOSED

    def initialize(cycle_action:)
      @cycle_action = cycle_action
      @report_errors = false
      @copied = false
    end

    def run
      catch_error(context: { cycle_action_id: cycle_action.id }) { run! }
    end

    def run!
      raise ServiceError, CLOSED if cycle_action.cycle.closed?

      CycleAction.transaction do
        # Verrou sur l'origine : deux clics rapprochés s'exécutent l'un après
        # l'autre, le second voit donc la copie du premier et la retire.
        cycle_action.lock!
        existing = CycleAction.find_by(copied_from_id: cycle_action.id)

        if existing
          @copy = existing
          @target_cycle = existing.cycle
          existing.soft_delete!(validate: false)
        else
          @target_cycle = cycle_action.cycle.next_cycle
          raise ServiceError, NO_NEXT_CYCLE unless target_cycle
          @copy = create_copy!
          @copied = true
        end
      end
      true
    end

    def copied?
      @copied
    end

    private

    # Mêmes libellé, catégorie, heures ESTIMÉES, nature économique et pôle ; tout ce
    # qui mesure l'avancement repart à zéro. La position n'est pas passée :
    # `set_default_position` place la copie en fin de sa catégorie.
    def create_copy!
      CycleAction.create!(
        cycle: target_cycle,
        human: cycle_action.human,
        delegate_to_human: cycle_action.delegate_to_human,
        label: cycle_action.label,
        category: cycle_action.category,
        unit_hours: cycle_action.unit_hours,
        hours: cycle_action.hours,
        occurrences: cycle_action.occurrences,
        completed_occurrences: 0,
        economic: cycle_action.economic,
        team_id: cycle_action.team_id,
        actual_hours: 0,
        completed: false,
        outcome: nil,
        archived_at: nil,
        deferral_count: 0,
        deferred_from: nil,
        copied_from: cycle_action
      )
    end
  end
end
