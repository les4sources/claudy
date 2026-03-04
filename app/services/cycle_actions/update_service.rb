module CycleActions
  class UpdateService < ServiceBase
    attr_reader :cycle_action

    def initialize(cycle_action:)
      @cycle_action = cycle_action
      @report_errors = true
    end

    def run(params = {})
      catch_error(context: { params: params }) { run!(params) }
    end

    def run!(params = {})
      cycle_action.attributes = cycle_action_params(params)
      cycle_action.save!
      true
    end

    private

    def cycle_action_params(params)
      params.require(:cycle_action).permit(
        :label, :hours, :category, :completed,
        :human_id, :delegate_to_human_id
      )
    end
  end
end
