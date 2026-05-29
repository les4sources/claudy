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

      def update
        @space_booking = SpaceBooking.find(params[:id])
        if @space_booking.update(space_booking_params)
          render :show
        else
          render_invalid(@space_booking)
        end
      end

      def destroy
        SpaceBooking.find(params[:id]).soft_delete!
        head :no_content
      end

      private

      def space_booking_params
        params.require(:space_booking).permit(
          :firstname, :lastname, :group_name, :phone, :email, :from_date, :to_date,
          :status, :tier, :payment_status, :invoice_status, :contract_status, :notes,
          :public_notes, :price_cents, :payment_method, :event_id, :paid_amount_cents,
          :deposit_amount_cents, :advance_amount_cents, :persons, :arrival_time,
          :departure_time, :option_kitchenware, :option_beamer, :option_wifi, :option_tables
        )
      end
    end
  end
end
