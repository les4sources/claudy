module Api
  module V1
    class HumansController < BaseController
      def index
        @humans = paginate(Human.all)
      end

      def show
        @human = Human.find(params[:id])
      end

      def update
        @human = Human.find(params[:id])
        if @human.update(human_params)
          render :show
        else
          render_invalid(@human)
        end
      end

      def destroy
        Human.find(params[:id]).soft_delete!
        head :no_content
      end

      private

      def human_params
        params.require(:human).permit(:name, :email, :photo, :summary, :description, :status, :cycle_active)
      end
    end
  end
end
