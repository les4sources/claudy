module Customers

  class CreateService < ServiceBase

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
          @customer.save
        end
    end

    private
    
    def customer_params(params)
      params
      .require(:stay).require(:customer_attributes)
        .permit(
          :firstname,
          :lastname,
          :email,
          :phone
        )
    end
  end
end
