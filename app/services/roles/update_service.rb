module Roles
  class UpdateService < ServiceBase
    PreconditionFailedError = Class.new(StandardError)

    attr_reader :role

    def initialize(role:)
      @role = role
      @report_errors = true
    end

    def run(params = {})
      context = {
        params: params
      }

      catch_error(context: context) do
        run!(params)
      end
    end

    def run!(params = {})
      role.attributes = role_params(params)
      # Remove empty human ID
      role.role_team.delete("")
      role.save!
      true
    end

    private

    def role_params(params)
      params
        .require(:role)
        .permit(
          :name,
          role_team: []
        )
    end
  end
end
