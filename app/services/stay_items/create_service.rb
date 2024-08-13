module StayItems
  class CreateService < ServiceBase
    attr_reader :stay
    attr_reader :stay_item

    def initialize(stay_id:)
      @stay = Stay.find(stay_id)
      @stay_item = @stay.stay_items.new
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
      stay_item.attributes = stay_item_params(params)
      stay_item.item_type = stay_item.item_type.camelize
      
      # temp fix for setting start_date (can't be null in database)
      stay_item.start_date = Date.today if stay_item.start_date.nil?

      stay_item.end_date = stay_item.start_date if stay_item.end_date.nil?
      stay_item.save!
      true
    end

    private

    def stay_item_params(params)
      params
        .require(:stay_item)
        .permit(
          :item_id,
          :item_type,
          :quantity,
          :start_date,
          :end_date,
          :unit_price,
          :adults_count,
          :children_count,
          :duration
        )
    end
  end
end
