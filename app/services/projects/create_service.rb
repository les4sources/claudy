module Projects
  class CreateService < ServiceBase
    attr_reader :project

    def initialize
      @project = Project.new
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
      project.attributes = project_params(params)
      project.save!
      true
    end

    private

    def project_params(params)
      params
        .require(:project)
        .permit(
          :name,
          :description,
          :due_date,
          :human_id
        )
    end
  end
end
