# Les tâches de gestion de la carte (epic #348, phase 6).
#
# Trois usages : la section « Tâches » de la fiche latérale (création,
# modification, suppression en Turbo Stream, sans recharger la fiche ni la
# carte), le carnet `/map/carnet` (douze mois, une section par mois), et la
# vue « ce mois-ci » de la carte, qui lit les objets concernés en JSON.
#
# Le porteur d’une tâche — objet de la carte ou plante (phase 7) — vient
# TOUJOURS de la route (`/map/features/:id/tasks`, `/map/plants/:id/tasks`)
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
    tasks = MapTask.with_live_subject.in_month(month)
    ids = tasks.where(subject_type: "MapFeature").distinct.pluck(:subject_id)
    # Une plante n'a de point sur la carte que placée : c'est lui qu'on signale.
    ids |= Plant.placed.where(id: tasks.where(subject_type: "Plant").select(:subject_id)).pluck(:map_feature_id)
    render json: { month: month, month_name: MapTask.month_name(month), feature_ids: ids.sort }
  end

  # POST /map/features/:map_feature_id/tasks ou /map/plants/:plant_id/tasks :
  # le TYPE du porteur vient de la route, jamais d'un paramètre.
  def create
    subject = params[:plant_id] ? Plant.find(params[:plant_id]) : MapFeature.find(params[:map_feature_id])
    @task = subject.map_tasks.new(created_by: current_user)
    @task.assign_attributes(task_params)
    respond(@task.save, subject)
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
  # effacerait ce qu'on est en train de saisir dans le formulaire du porteur
  # (`dom_id(feature, :tasks)` ou `dom_id(plant, :tasks)`).
  def respond(saved, subject)
    invalid = saved ? nil : @task
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(subject, :tasks),
                                                  partial: "maps/feature_tasks",
                                                  locals: { subject: subject, invalid_task: invalid }),
               status: saved ? :ok : :unprocessable_content
      end
      format.html do
        feature_id = subject.is_a?(Plant) ? subject.map_feature_id : subject.id
        redirect_to map_path(feature: feature_id), alert: (saved ? nil : @task.errors.full_messages.to_sentence)
      end
    end
  end
end
