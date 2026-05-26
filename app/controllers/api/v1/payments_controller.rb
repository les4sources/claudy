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
    end
  end
end
