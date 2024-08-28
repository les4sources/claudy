module StayItems
  class UpdateService < ServiceBase
    
    attr_reader :stay_item

    def initialize(stay_item_id:)
      @stay_item = StayItem.find(stay_item_id)
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
          :babies_count,
          :duration,
          :calculated_price
        )
    end
  end
end
