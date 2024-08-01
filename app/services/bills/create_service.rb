module Bills

  class CreateService < ServiceBase
    
    attr_reader :blll
    attr_reader :stay

    def initialize(stay_id)
      @stay = Stay.find(stay_id)
      @bill = @stay.bills.new
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
      @bill.attributes = bill_params(params)
      return false if !@bill.valid?
      @bill.save!
      raise error_message if !error.nil?
      true
    end

    private

     def bill_params(params)
      params
        .require(:bill)
        .permit(
          :total_amount,
          :payment_method
        )
    end

  end
end
