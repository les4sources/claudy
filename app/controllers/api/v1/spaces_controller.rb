module Api
  module V1
    class SpacesController < BaseController
      def index
        @spaces = paginate(Space.all)
      end

      def show
        @space = Space.find(params[:id])
      end

      def update
        @space = Space.find(params[:id])
        if @space.update(space_params)
          render :show
        else
          render_invalid(@space)
        end
      end

      def destroy
        Space.find(params[:id]).soft_delete!
        head :no_content
      end

      private

      def space_params
        params.require(:space).permit(:name, :description, :code, :position)
      end
    end
  end
end
