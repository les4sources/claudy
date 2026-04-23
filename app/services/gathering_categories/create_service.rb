module GatheringCategories
  class CreateService < ServiceBase
    attr_reader :gathering_category

    def initialize
      @gathering_category = GatheringCategory.new
      @report_errors = true
    end

    def run(params = {})
      context = { params: params }

      catch_error(context: context) do
        run!(params)
      end
    end

    def run!(params = {})
      gathering_category.attributes = gathering_category_params(params)
      gathering_category.save!
      true
    end

    private

    def gathering_category_params(params)
      params
        .require(:gathering_category)
        .permit(
          :name,
          :color,
          :default_start_time,
          :default_duration_minutes
        )
    end
  end
end
