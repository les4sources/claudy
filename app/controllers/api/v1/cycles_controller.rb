module Api
  module V1
    class CyclesController < BaseController
      def index
        @cycles = paginate(Cycle.chronological)
      end

      def show
        @cycle = Cycle.find(params[:id])
      end

      def update
        @cycle = Cycle.find(params[:id])
        if @cycle.update(cycle_params)
          render :show
        else
          render_invalid(@cycle)
        end
      end

      def destroy
        Cycle.find(params[:id]).soft_delete!
        head :no_content
      end

      private

      def cycle_params
        params.require(:cycle).permit(:name, :start_date, :end_date)
      end
    end
  end
end
