module Payments
  class CreateService < ServiceBase
    attr_reader :booking
    attr_reader :payment

    def initialize(booking_id:)
      @booking = Booking.find(booking_id)
      @payment = @booking.payments.new
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
      set_status
      # Stay-first (epic #26, Phases 3-4) : le stay est désormais OBLIGATOIRE sur
      # Payment. On l'assigne AVANT de valider — sinon la validation de présence
      # échoue et le paiement admin n'est jamais créé. EnsureForBooking peut créer
      # un Stay : on l'exécute dans la transaction pour que tout soit atomique (le
      # Stay est annulé si le paiement se révèle finalement invalide).
      saved = false
      ActiveRecord::Base.transaction do
        @payment.stay = Stays::EnsureForBooking.call(@booking)
        if @payment.valid?
          @payment.save!
          saved = true
        else
          raise ActiveRecord::Rollback
        end
      end
      return false unless saved

      @booking.set_payment_status
      raise error_message if !error.nil?
      true
    end

    private

    def set_status
      case @payment.payment_method
      when "airbnb"
        @payment.status = "paid"
      when "bookingdotcom"
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
  end
end
