module Stays

  class CreateService < ServiceBase
    include Bookable
    include Subscribable

    attr_reader :stay

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
      Rails.logger.info(params)

      customer_service = Customers::CreateService.new
      customer_service.run(params)
      @stay.attributes = stay_params(params).except(:customer_attributes)
      @stay.customer = customer_service.customer
      @stay.generate_token
      @stay.user_id = User.first.id
      @stay.save!
      return false if !@stay.valid?
      raise error_message if !error.nil?
      true
    end
  end
end
