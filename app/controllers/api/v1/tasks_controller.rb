module Api
  module V1
    class TasksController < BaseController
      def index
        scope = Task.all
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(project_id: params[:project_id]) if params[:project_id].present?
        @tasks = paginate(scope.includes(:humans).order(:due_date))
      end

      def show
        @task = Task.includes(:humans).find(params[:id])
      end
    end
  end
end
