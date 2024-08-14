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
      @stay.draft = false
      # temporary
      # @stay.customer = Customer.create(firstname: "Johnny")
      @stay.save!
      raise error_message if !error.nil?
      true
    end
  end
end
