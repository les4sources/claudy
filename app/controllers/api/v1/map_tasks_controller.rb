module Api
  module V1
    # Les tâches de gestion de la carte (epic #348, phase 8) : « Taille
    # d'hiver », en février, sur une plante ou un objet de la carte. À ne pas
    # confondre avec `TasksController`, les tâches du collectif.
    #
    # Le porteur se donne par `subject_type` (liste fermée : MapFeature, Plant)
    # et `subject_id`, et ne change plus ensuite.
    class MapTasksController < BaseController
      include MapWriting

      def index
        scope = MapTask.with_live_subject.ordered
        scope = scope.where(subject_type: params[:subject_type]) if params[:subject_type].present?
        scope = scope.where(subject_id: params[:subject_id]) if params[:subject_id].present?
        scope = scope.in_month(params[:month]) if params[:month].present?
        @map_tasks = paginate(scope)
      end

      def show
        @map_task = MapTask.find(params[:id])
      end

      def create
        body = params.require(:map_task)
        errors = []
        type = closed_value("subject_type", body[:subject_type], MapTask::SUBJECT_TYPES.keys.index_with(&:itself), errors)
        errors << "subject_type est obligatoire" if body[:subject_type].blank?
        subject = type.constantize.find_by(id: body[:subject_id]) if type
        errors << "subject_id #{body[:subject_id].inspect} : aucun #{type} vivant" if type && subject.nil?
        attributes = task_attributes(errors)
        return render_errors(errors) if errors.any?

        @map_task = MapTask.create!(attributes.merge(subject: subject))
        render :show, status: :created
      end

      def update
        @map_task = MapTask.find(params[:id])
        errors = []
        attributes = task_attributes(errors)
        return render_errors(errors) if errors.any?

        @map_task.update!(attributes)
        render :show
      end

      def destroy
        MapTask.find(params[:id]).soft_delete!(validate: false)
        head :no_content
      end

      private

      def task_attributes(errors)
        attributes = params.require(:map_task).permit(:label, :sector, :frequency, :notes, months: []).to_h.symbolize_keys
        attributes[:sector] = closed_value("sector", attributes[:sector], MapTask::SECTORS, errors) if attributes.key?(:sector)
        attributes
      end
    end
  end
end
