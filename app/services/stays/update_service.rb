module Stays
  class UpdateService < ServiceBase
    include Bookable

    attr_reader :stay

    def initialize(stay_id:)
      @report_errors = true
      @stay = Stay.find_by!(id: stay_id)
    end

    def run(params = {})
      context = {
        params: params,
        stay: stay&.attributes
      }

      catch_error(context: context) do
        run!(params)
      end
    end

    def run!(params = {})
    
      @stay.attributes = stay_params(params)
      return false if !@stay.valid?
      ActiveRecord::Base.transaction do
        # delete previous reservations as we will re-create them
        @stay.stay_item_dates.destroy_all
        begin
          if is_available?
            Rails.logger.info("$$$$$$$ BEFORE BUILD")
            @stay.build_booked_item
            @stay.draft = false
          end
        rescue ActiveRecord::RecordNotUnique => e
          set_error_message("L'un des élément d'hébergement est déjà occupé à ces dates. Veuillez vérifier.")
          raise error_message
          true
        end

      end
      customer_service = Customers::CreateService.new
      customer_service.run(params)
      @stay.customer = customer_service.customer
      @stay.save!
      @stay.set_payment_status
      raise error_message if !error.nil?
      true
    end

    private

    def stay_params(params)
      params
        .require(:stay)
        .permit(
          :adults,
          :children,
          :babies,
          :departure_time,
          :estimated_arrival,
          :start_date,
          :end_date,
          :status,
          :platform,
          :group_name,
          :notes,
          :public_notes,
          :invoice_status,
          :final_price,
          customer_attributes: [
            :id,
            :firstname,
            :lastname,
            :email,
            :phone
          ],
          payments_attributes: [
            :id,
            :amount,
            :payment_method,
            :_destroy
        ]
        )
    end
 end
end
