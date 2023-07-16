module Teams
  class CreateService < ServiceBase
    attr_reader :team

    def initialize
      @team = Team.new
      @report_errors = true
    end

    def run(params = {})
      context = {
        params: params,
      }

      catch_error(context: context) do
        run!(params)
      end
    end

    def run!(params = {})
      team.attributes = team_params(params)
      team.save!
      true
    end

    private

    def team_params(params)
      params
        .require(:team)
        .permit(
          :name,
          :description
        )
    end
  end
end
