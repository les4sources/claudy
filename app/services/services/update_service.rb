module Services
  class UpdateService < ServiceBase
    PreconditionFailedError = Class.new(StandardError)

    attr_reader :service

    def initialize(service:)
      @service = service
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
      service.attributes = service_params(params)
      service.save!
      true
    end

    private

    def service_params(params)
      params
        .require(:service)
        .permit(
          :name,
          :human_id,
          :summary,
          :description,
          :price,
          :photo,
          :photo_cache
        )
    end
  end
end
