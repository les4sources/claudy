module Api
  module V1
    class BookingsController < BaseController
      def index
        scope = Booking.all
        scope = scope.where("to_date >= ?", params[:from_date]) if params[:from_date].present?
        scope = scope.where("from_date <= ?", params[:to_date]) if params[:to_date].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(lodging_id: params[:lodging_id]) if params[:lodging_id].present?
        @bookings = paginate(scope.includes(:lodging).order(from_date: :asc))
      end

      def show
        @booking = Booking.includes(reservations: :room).find(params[:id])
      end
    end
  end
end
