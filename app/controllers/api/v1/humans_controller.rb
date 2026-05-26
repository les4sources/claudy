module Api
  module V1
    class HumansController < BaseController
      def index
        @humans = paginate(Human.all)
      end

      def show
        @human = Human.find(params[:id])
      end
    end
  end
end
