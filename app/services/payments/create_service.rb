module Payments
  class CreateService < ServiceBase
    #attr_reader :booking
    attr_reader :payment
    attr_reader :reservation

    def initialize(reservation_type:, reservation_id:)
      @reservation = get_reservation(reservation_type, reservation_id)
      @payment = @reservation.payments.new
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
      @payment.attributes = payment_params(params)
      return false if !@payment.valid?
      set_status
      @payment.save!
      @reservation.set_payment_status
      raise error_message if !error.nil?
      true
    end

    private

    def set_status
      case @payment.payment_method
      when "airbnb"
        @payment.status = "paid"
      when "cash"
        @payment.status = "paid"
      when "bank_transfer"
        @payment.status = "paid"
      when "stripe"
        @payment.status = "pending"
      end
    end

    def payment_params(params)
      params
        .require(:payment)
        .permit(
          :amount,
          :payment_method
        )
    end

   def get_reservation(reservation_type, reservation_id)
      case reservation_type
      when 'Booking'
        Booking.find(reservation_id)
      when 'Stay'
        Stay.find(reservation_id)
      else
        raise ArgumentError, "Unsupported reservation type: #{reservation_type}"
      end
  end


  end
end
