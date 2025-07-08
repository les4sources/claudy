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
      # Handle both direct customer creation and nested attributes from stays
      if params[:customer].present?
        # Direct customer creation
        @customer.attributes = customer_params(params)
        @customer.save!
      elsif params[:stay]&.dig(:customer_attributes).present?
        # Nested attributes from stay creation
        @customer = Customer.find_or_initialize_by(email: params[:stay][:customer_attributes][:email])
        if @customer.new_record?
          @customer.attributes = nested_customer_params(params)
          @customer.save!
        end
      else
        raise ArgumentError, "No customer data provided"
      end
    end

    private
    
    def customer_params(params)
      params
        .require(:customer)
        .permit(
          :firstname,
          :lastname,
          :email,
          :phone,
          :notes,
          :company_name,
          :vat_number,
          :street,
          :number,
          :box,
          :postcode,
          :city,
          :country
        )
    end

    def nested_customer_params(params)
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
