module Api
  module V1
    # Rôles datés assignés aux membres — notamment les gardes (role "Veilleur·euse").
    # Un HumanRole = un membre tient un rôle un jour donné, avec un statut
    # (selected = confirmé, backup = suppléant). Read-only : la planification des
    # gardes se gère ailleurs ; l'API ne fait que l'exposer.
    class HumanRolesController < BaseController
      def index
        scope = HumanRole.all
        scope = scope.where(human_id: params[:human_id]) if params[:human_id].present?
        scope = scope.where(role_id: params[:role_id]) if params[:role_id].present?
        scope = scope.where(status: params[:status]) if HumanRole.statuses.key?(params[:status])
        scope = scope.where("date >= ?", params[:from]) if params[:from].present?
        scope = scope.where("date <= ?", params[:to]) if params[:to].present?
        @human_roles = paginate(scope.includes(:human, :role).order(:date))
      end

      def show
        @human_role = HumanRole.includes(:human, :role).find(params[:id])
      end
    end
  end
end
