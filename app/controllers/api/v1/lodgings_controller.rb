module Api
  module V1
    class LodgingsController < BaseController
      def index
        @lodgings = paginate(Lodging.order(:name))
      end

      def show
        @lodging = Lodging.includes(:rooms).find(params[:id])
      end
    end
  end
end
