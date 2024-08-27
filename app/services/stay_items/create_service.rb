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

      # set the unit price from the item
      set_item_price(stay_item)

      stay_item.end_date = stay_item.start_date if stay_item.end_date.nil?
      stay_item.save!
      true
    end


    private

    def set_item_price(stay_item)

      case stay_item.item_type
      when StayItem::LODGING
        item = Lodging.find(stay_item.item_id)
        stay_item.unit_price_cents = item.price_night_cents
      when StayItem::ROOM
        item = Room.find(stay_item.item_id)
        stay_item.unit_price_cents = item.price_night_cents
      when StayItem::BED
        item = Bed.find(stay_item.item_id)
        stay_item.unit_price_cents = item.price_cents
      when StayItem::EXPERIENCE
        item = Experience.find(stay_item.item_id)
        stay_item.unit_price_cents = item.fixed_price_cents   # price or fixed_price?
      when StayItem::PRODUCT
        item = Product.find(stay_item.item_id)
        stay_item.unit_price_cents = item.price_cents 
      when StayItem::RENTAL_ITEM
        item = RentalItem.find(stay_item.item_id)
        stay_item.unit_price_cents = item.price_cents
      end

    end


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
          :duration
        )
    end
  end
end
