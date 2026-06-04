module GatheringActions
  class CreateService < ServiceBase
    attr_reader :gathering_action

    def initialize(gathering:)
      @gathering_action = gathering.gathering_actions.build
      @report_errors = true
    end

    def run(params = {})
      context = { params: params }
      catch_error(context: context) { run!(params) }
    end

    def run!(params = {})
      attrs = gathering_action_params(params)
      human_ids = Array(attrs.delete(:human_ids)).reject(&:blank?)
      gathering_action.attributes = attrs
      gathering_action.assignee_ids = human_ids
      gathering_action.save!
      true
    end

    private

    def gathering_action_params(params)
      params.require(:gathering_action).permit(:label, human_ids: [])
    end
  end
end
