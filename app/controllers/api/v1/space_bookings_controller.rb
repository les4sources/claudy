module Api
  module V1
    class SpaceBookingsController < BaseController
      def index
        scope = SpaceBooking.all
        scope = scope.where("to_date >= ?", params[:from_date]) if params[:from_date].present?
        scope = scope.where("from_date <= ?", params[:to_date]) if params[:to_date].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        @space_bookings = paginate(scope.includes(:spaces).order(from_date: :asc))
      end

      def show
        @space_booking = SpaceBooking.includes(space_reservations: :space).find(params[:id])
      end
    end
  end
end
