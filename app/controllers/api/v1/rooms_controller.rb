module Api
  module V1
    class RoomsController < BaseController
      def index
        @rooms = paginate(Room.includes(:lodgings).order(:name))
      end

      def show
        @room = Room.includes(:lodgings).find(params[:id])
      end
    end
  end
end
