# Les tâches de gestion de la carte (epic #348, phase 6).
#
# Trois usages : la section « Tâches » de la fiche latérale (création,
# modification, suppression en Turbo Stream, sans recharger la fiche ni la
# carte), le carnet `/map/carnet` (douze mois, une section par mois), et la
# vue « ce mois-ci » de la carte, qui lit les objets concernés en JSON.
#
# Le porteur d'une tâche vient TOUJOURS de la route (`/map/features/:id/tasks`)
# ou de la tâche existante : `subject_type` n'est jamais lu dans les
# paramètres, donc jamais constantizé depuis une saisie.
class MapTasksController < BaseController
  before_action :get_task, only: %i[update destroy]

  # GET /map/carnet?sector=terrain — les tâches de l'année, mois par mois. Une
  # tâche de mars et d'octobre apparaît dans les deux sections.
  def index
    @sector = MapTask::SECTORS.key?(params[:sector]) ? params[:sector] : nil
    @current_month = Date.current.month
    tasks = MapTask.with_live_subject.in_sector(@sector).includes(:subject)
                   .order(:label, :id).to_a
    @tasks_by_month = MapTask::MONTHS.index_with { |month| tasks.select { |task| task.months.include?(month) } }
    @undated = tasks.select { |task| task.months.empty? }
  end

  # GET /map/tasks/current.json — les objets porteurs d'une tâche du mois en
  # cours, pour la vue « ce mois-ci » de la carte.
  def current
    month = Date.current.month
    ids = MapTask.with_live_subject.in_month(month).where(subject_type: "MapFeature").distinct.pluck(:subject_id)
    render json: { month: month, month_name: MapTask.month_name(month), feature_ids: ids }
  end

  def create
    feature = MapFeature.find(params[:map_feature_id])
    @task = feature.map_tasks.new(created_by: current_user)
    @task.assign_attributes(task_params)
    respond(@task.save, feature)
  end

  def update
    respond(@task.update(task_params), @task.subject)
  end

  def destroy
    @task.soft_delete!(validate: false)
    respond(true, @task.subject)
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end

  # La tâche d'un objet supprimé n'existe plus pour personne : 404.
  def get_task
    @task = MapTask.with_live_subject.find(params[:id])
  end

  def task_params
    params.require(:map_task).permit(:label, :sector, :frequency, :notes, months: [])
  end

  # Seule la section « Tâches » est remplacée : re-rendre toute la fiche
  # effacerait ce qu'on est en train de saisir dans le formulaire de l'objet.
  def respond(saved, feature)
    invalid = saved ? nil : @task
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(feature, :tasks),
                                                  partial: "maps/feature_tasks",
                                                  locals: { feature: feature, invalid_task: invalid }),
               status: saved ? :ok : :unprocessable_content
      end
      format.html do
        redirect_to map_path(feature: feature.id), alert: (saved ? nil : @task.errors.full_messages.to_sentence)
      end
    end
  end
end
