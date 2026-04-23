module Decisions
  class UpdateService < ServiceBase
    attr_reader :decision

    def initialize(decision:)
      @decision = decision
      @report_errors = true
    end

    def run(params = {})
      context = { params: params }
      catch_error(context: context) { run!(params) }
    end

    def run!(params = {})
      decision.attributes = decision_params(params)
      decision.save!
      true
    end

    private

    def decision_params(params)
      params.require(:decision).permit(
        :title,
        :summary,
        :body,
        :taken_at,
        :gathering_id,
        :agenda_item_id
      )
    end
  end
end
