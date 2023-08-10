class TasksController < BaseController
    before_action :get_task, only: [:show, :edit, :update, :destroy]
  
    breadcrumb "Actions", :tasks_path, match: :exact
  
    def index
      @tasks = TaskDecorator
        .decorate_collection(Task.all.order(name: :asc))
    end
  
    def show
      @task = TaskDecorator.new(@task)
    end
  
    def new
      @task = Task.new(project_id: params[:project_id], bundle_id: params[:bundle_id])
    end
  
    def create
      service = Tasks::CreateService.new
      if service.run(params)
        respond_to do |format|
          format.html { 
            redirect_to task_path(service.task),
                        notice: "Super! L'action a été ajoutée. Il n'y a plus qu'à!"
          }
          format.turbo_stream {
            @task = service.task
          }
        end
      else
        @task = service.task
        set_error_flash(service.task, service.error_message)
        render :new
      end
    end
  
    def edit
    end
  
    def update
      service = Tasks::UpdateService.new(
        task: Task.find(params[:id])
      )
      if service.run(params)
        redirect_to task_path(service.task),
                    notice: "L'action a été mise à jour."
      else
        @task = service.task
        set_error_flash(service.task, service.error_message)
        render :edit
      end
    end
  
    def destroy
      if @task.soft_delete!(validate: false)
        respond_to do |format|
          format.html { 
            redirect_to tasks_path,
                        notice: "L'action '#{@task.name}' a été supprimée."
          }
          format.turbo_stream
        end
      else
        flash.now[:alert] = "Une erreur est survenue."
        render :show
      end
    end
  
    private
  
    def get_task
      @task = Task.find(params[:id])
    end
  
    def set_presenters
      @menu_presenter = Components::MenuPresenter.new(
        active_primary: "projects",
        active_secondary: "tasks"
      )
      @projects_view = true
    end
  end
  