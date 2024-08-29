module StayPrices
  class CalculationService < ServiceBase
    
    include Bookable

    attr_reader :stay, :stay_item, :item, :amount





    def initialize
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
      
      if params[:item_type].present?
         
         method_name = "calculate_price_for_#{params[:item_type].downcase}"

         if respond_to?(method_name, true)
          @amount = send(method_name, params)
         else
          raise ArgumentError, "Invalid item type: #{params[:item_type]}"
         end
      end
      true

    end


    private

    def calculate_price_for_product(params)
        product = Product.find(params[:item_id])
        price = 0
        if product
          price = BigDecimal(product.price_cents) * BigDecimal(params[:quantity])
        end
        (price/100)
    end

    def calculate_price_for_experience(params)
        experience = Experience.find(params[:item_id])
        price = 0
        price_for_adult = 0
        price_for_children = 0
        if experience
          # TODO: how to include duration in the calcul of the price?
          adult_count = params[:adult_count] || 0
          children_count = params[:children_count] || 0
          Rails.logger.info("#{adult_count == 0}")
          Rails.logger.info("#{children_count == 0}")
          price_for_adult = BigDecimal(experience.price_cents) * BigDecimal(adult_count) unless adult_count == 0
          price_for_children = BigDecimal(experience.price_cents) * BigDecimal(children_count) * 0.5 unless children_count == 0
          Rails.logger.info("#{price_for_adult}")
          Rails.logger.info("#{price_for_children}")
          price = price_for_adult + price_for_children
        end
        (price/100)
    end

    def calculate_price_for_rentalitem(params)
        item = RentalItem.find(params[:item_id])
        price = 0
        if item
          start_date = Date.parse(params[:start_date])
          end_date = Date.parse(params[:end_date])
          quantity = params[:quantity].to_i 
          night_count = (end_date - start_date).to_i
          price = BigDecimal(night_count) * BigDecimal(quantity) * BigDecimal(item.price_cents) unless quantity == 0 || night_count == 0
        end
        (price/100)
    end


    def calculate_price_for_space(params)
      item = Space.find(params[:item_id])
      price = 0
      duration = params[:duration]
      price = item.price(duration)
      (price/100)
    end

    def calculate_price_for_lodging(params)
        calculate_price_for(Lodging.find(params[:item_id]), params)
        
    end

    def calculate_price_for_room(params)
        calculate_price_for(Room.find(params[:item_id]), params)
    end

    def calculate_price_for_bed(params)
        calculate_price_for(Bed.find(params[:item_id]), params)
    end

    def calculate_price_for(item, params)
        price = 0
        if item
          start_date = Date.parse(params[:start_date])
          end_date = Date.parse(params[:end_date])
          night_count = (end_date - start_date).to_i
          if night_count >0 && night_count <= 6
            price = item.price(night_count)
          elsif night_count > 6
            price = item.price(1) * night_count  
          end
        end
        (price/100)
    end
    
  end
end

  
