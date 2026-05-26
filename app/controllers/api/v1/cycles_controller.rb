module Api
  module V1
    class CyclesController < BaseController
      def index
        @cycles = paginate(Cycle.chronological)
      end

      def show
        @cycle = Cycle.find(params[:id])
      end
    end
  end
end
