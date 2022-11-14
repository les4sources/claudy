module EventCategories
  class CreateService < ServiceBase
    attr_reader :event_category

    def initialize
      @event_category = EventCategory.new
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
      event_category.attributes = event_category_params(params)
      event_category.save!
      true
    end

    private

    def event_category_params(params)
      params
        .require(:event_category)
        .permit(
          :name,
          :color
        )
    end
  end
end
