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

      def update
        @task = Task.find(params[:id])
        if @task.update(task_params)
          render :show
        else
          render_invalid(@task)
        end
      end

      def destroy
        Task.find(params[:id]).soft_delete!
        head :no_content
      end

      private

      def task_params
        params.require(:task).permit(:name, :description, :status, :due_date, :project_id, :bundle_id)
      end
    end
  end
end
