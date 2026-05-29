module Api
  module V1
    class RoomsController < BaseController
      def index
        @rooms = paginate(Room.includes(:lodgings).order(:name))
      end

      def show
        @room = Room.includes(:lodgings).find(params[:id])
      end

      def update
        @room = Room.find(params[:id])
        if @room.update(room_params)
          render :show
        else
          render_invalid(@room)
        end
      end

      def destroy
        Room.find(params[:id]).soft_delete!
        head :no_content
      end

      private

      def room_params
        params.require(:room).permit(:name, :description, :level, :code)
      end
    end
  end
end
