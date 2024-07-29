module Customers

  class CreateService < ServiceBase

    include Bookable

    attr_reader :customer

    def initialize
      @customer = Customer.new
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

      @customer = Customer.find_or_initialize_by(email: params[:stay][:customer_attributes][:email])
        if @customer.new_record?
          @customer.attributes = customer_params(params)
          if @customer.save
            Rails.logger.debug "Customer created: #{@customer.inspect}"
          else
            Rails.logger.debug "Customer errors: #{@customer.errors.full_messages}"
          end
        else
          Rails.logger.debug "Customer found: #{@customer.inspect}"
        end

    end
  end
end
