module StayPrices
  class CalculationService < ServiceBase
    include Bookable

    attr_reader :stay, :amount

    def initialize
      @stay = Stay.new
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
      #@booking.attributes = booking_params(params)
      @amount = calculate_price
      true
    end

    private


    def _calculate_price
      
      @stay.stay_items.each do |stay_item|

        

      end

    end


    def calculate_price
      case @booking.booking_type
      when "lodging"
        calculate_price_for_lodging
      when "rooms"
        calculate_price_for_rooms
      end
    end

    def calculate_price_for_rooms
      # tier pricing (25 / 35 / 45)
      # price per person (adults and children)
      # 20% discount starting from 3rd night
      total_amount = 0
      case @booking.tier_rooms
      when "solidaire"
        night_price = 2500
      when "neutre"
        night_price = 3500
      when "soutien"
        night_price = 4500
      end
      nights_count = 0
      (@booking.from_date..@booking.to_date.yesterday).each do |date|
        nights_count = nights_count + 1
        if nights_count > 2
          night_amount = night_price * 0.8 # 20% discount
        else
          night_amount = night_price
        end
        total_amount = total_amount + night_amount
      end
      total_amount * (@booking.adults + @booking.children)
    end

    def calculate_price_for_lodging
      # tier pricing (-25%, standard, +25%)
      # 20% discount starting from 2nd night
      # 6% discount on weekend nights (Fri and Sat)
      total_amount = 0
      case @booking.tier_lodgings
      when "solidaire"
        night_price = @booking.lodging.price_night_cents * 0.75
      when "neutre"
        night_price = @booking.lodging.price_night_cents
      when "soutien"
        night_price = @booking.lodging.price_night_cents * 1.25
      end
      nights_count = 0
      (@booking.from_date..@booking.to_date.yesterday).each do |date|
        nights_count = nights_count + 1
        if date.wday == 5 || date.wday == 6 # Fri, Sat
          night_amount = night_price * 0.94 # 6% discount
        else
          night_amount = night_price
        end
        if nights_count > 1
          night_amount = night_amount * 0.8 # 20% discount
        end
        total_amount = total_amount + night_amount
      end
      total_amount
    end
  end
end

  
