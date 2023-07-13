module Humans
  class UpdateService < ServiceBase
    PreconditionFailedError = Class.new(StandardError)

    attr_reader :human

    def initialize(human:)
      @human = human
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
      human.attributes = human_params(params)
      human.save!
      true
    end

    private

    def human_params(params)
      params
        .require(:human)
        .permit(
          :name,
          :email,
          :summary,
          :description,
          :photo
        )
    end
  end
end
