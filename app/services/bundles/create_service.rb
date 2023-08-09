module Bundles
  class CreateService < ServiceBase
    attr_reader :bundle

    def initialize
      @bundle = Bundle.new
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
      bundle.attributes = bundle_params(params)
      bundle.save!
      true
    end

    private

    def bundle_params(params)
      params
        .require(:bundle)
        .permit(
          :name,
          :project_id,
          :team_id,
          :position
        )
    end
  end
end
