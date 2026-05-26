module Api
  module V1
    class SpacesController < BaseController
      def index
        @spaces = paginate(Space.all)
      end

      def show
        @space = Space.find(params[:id])
      end
    end
  end
end
