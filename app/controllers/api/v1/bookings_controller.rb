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

      def update
        @booking = Booking.find(params[:id])
        if @booking.update(booking_params)
          render :show
        else
          render_invalid(@booking)
        end
      end

      def destroy
        Booking.find(params[:id]).soft_delete!
        head :no_content
      end

      private

      def booking_params
        params.require(:booking).permit(
          :firstname, :lastname, :phone, :email, :from_date, :to_date, :status,
          :adults, :children, :babies, :payment_status, :payment_method, :bedsheets,
          :towels, :wifi, :notes, :public_notes, :comments, :price_cents,
          :shown_price_cents, :invoice_status, :contract_status, :estimated_arrival,
          :departure_time, :tier, :platform, :group_name, :lodging_id,
          :option_babysitting, :option_partyhall, :option_bread, :option_discgolf,
          :option_pizza_party
        )
      end
    end
  end
end
