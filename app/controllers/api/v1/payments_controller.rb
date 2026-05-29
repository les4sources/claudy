module Api
  module V1
    class PaymentsController < BaseController
      def index
        scope = Payment.all
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(booking_id: params[:booking_id]) if params[:booking_id].present?
        @payments = paginate(scope.includes(:booking).order(created_at: :desc))
      end

      def show
        @payment = Payment.includes(:booking).find(params[:id])
      end

      def update
        @payment = Payment.find(params[:id])
        if @payment.update(payment_params)
          render :show
        else
          render_invalid(@payment)
        end
      end

      def destroy
        Payment.find(params[:id]).soft_delete!
        head :no_content
      end

      private

      # Stripe identifiers are provider-managed and never writable via the API.
      def payment_params
        params.require(:payment).permit(:booking_id, :payment_method, :status, :amount_cents)
      end
    end
  end
end
