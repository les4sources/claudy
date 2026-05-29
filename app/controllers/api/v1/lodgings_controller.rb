module Api
  module V1
    class LodgingsController < BaseController
      def index
        @lodgings = paginate(Lodging.order(:name))
      end

      def show
        @lodging = Lodging.includes(:rooms).find(params[:id])
      end

      def update
        @lodging = Lodging.find(params[:id])
        if @lodging.update(lodging_params)
          render :show
        else
          render_invalid(@lodging)
        end
      end

      def destroy
        Lodging.find(params[:id]).soft_delete!
        head :no_content
      end

      private

      def lodging_params
        params.require(:lodging).permit(
          :name, :description, :summary, :price_night_cents, :weekend_discount_cents,
          :party_hall_availability, :show_on_reports, :available_for_bookings
        )
      end
    end
  end
end
