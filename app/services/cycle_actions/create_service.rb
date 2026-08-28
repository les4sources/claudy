module CycleActions
  class CreateService < ServiceBase
    attr_reader :cycle_action

    def initialize
      @cycle_action = CycleAction.new
      @report_errors = true
    end

    def run(params = {})
      catch_error(context: { params: params }) { run!(params) }
    end

    def run!(params = {})
      cycle_action.attributes = cycle_action_params(params)
      cycle_action.cycle ||= Cycle.reference_for
      raise ServiceError, "Aucun cycle n'est configuré : créez-en un d'abord." unless cycle_action.cycle
      raise ServiceError, "Ce cycle est clos." if cycle_action.cycle.closed?
      cycle_action.save!
      true
    end

    private

    def cycle_action_params(params)
      params.require(:cycle_action).permit(
        :label, :hours, :category, :completed,
        :human_id, :delegate_to_human_id, :cycle_id
      )
    end
  end
end
