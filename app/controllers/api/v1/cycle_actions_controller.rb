module Api
  module V1
    class CycleActionsController < BaseController
      def index
        scope = CycleAction.all
        scope = scope.where(human_id: params[:human_id]) if params[:human_id].present?
        scope = scope.where(category: params[:category]) if CycleAction.categories.key?(params[:category])
        if params[:completed].present?
          scope = scope.where(completed: ActiveModel::Type::Boolean.new.cast(params[:completed]))
        end
        @cycle_actions = paginate(scope.includes(:human, :delegate_to_human).ordered)
      end

      def show
        @cycle_action = CycleAction.includes(:human, :delegate_to_human).find(params[:id])
      end

      def update
        @cycle_action = CycleAction.find(params[:id])
        if @cycle_action.update(cycle_action_params)
          render :show
        else
          render_invalid(@cycle_action)
        end
      end

      def destroy
        CycleAction.find(params[:id]).soft_delete!
        head :no_content
      end

      private

      def cycle_action_params
        params.require(:cycle_action).permit(
          :label, :hours, :category, :completed, :human_id, :delegate_to_human_id,
          :position, :archived_at
        )
      end
    end
  end
end
