module Tasks
  class CreateService < ServiceBase
    attr_reader :task

    def initialize
      @task = Task.new
      @report_errors = true
    end

    def run(params = {})
      context = {
        params: params,
      }

      catch_error(context: context) do
        run!(params)
      end
    end

    def run!(params = {})
      task.attributes = task_params(params)
      task.save!
      true
    end

    private

    def task_params(params)
      params
        .require(:task)
        .permit(
          :name,
          :description,
          :due_date,
          :status,
          :project_id
        )
    end
  end
end
