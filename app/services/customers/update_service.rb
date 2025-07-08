module Customers

  class UpdateService < ServiceBase

    attr_reader :customer

    def initialize(customer:)
      @customer = customer
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
      @customer.attributes = customer_params(params)
      @customer.save!
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
  end
end 