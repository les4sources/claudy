module Spaces
  class UpdateService < ServiceBase
    PreconditionFailedError = Class.new(StandardError)

    attr_reader :space

    def initialize(space:)
      @space = space
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
      space.attributes = space_params(params)
      space.save!
      true
    end

    private

    def space_params(params)
      params
        .require(:space)
        .permit(
          :name,
          :description,
          :code,
          :position,
          :capacity
        )
    end
  end
end
