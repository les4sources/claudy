module Paylinks
  class DestroyService < ServiceBase
    attr_reader :booking
    attr_reader :paylink

    def initialize(paylink_id:)
      @paylink = Paylink.find(paylink_id)
      @booking = @paylink.booking
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
      @paylink.destroy
      raise error_message if !error.nil?
      true
    end
  end
end
