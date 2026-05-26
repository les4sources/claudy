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
    end
  end
end
