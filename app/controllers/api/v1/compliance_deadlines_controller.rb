module Api
  module V1
    # Les échéances de l'échéancier comptable. Pas de POST : une échéance naît
    # de sa règle. PATCH sert à clore, reporter, annoter — et à reprendre
    # l'historique (une TVA déposée en avril, close à la date du dépôt).
    class ComplianceDeadlinesController < BaseController
      before_action :get_deadline, only: [:show, :update]

      def index
        scope = ComplianceDeadline.ordered.includes(:purchase_invoice, compliance_obligation: :legal_entity)
        scope = scope.where(compliance_obligation_id: params[:compliance_obligation_id]) if params[:compliance_obligation_id].present?
        scope = scope.outstanding if ActiveModel::Type::Boolean.new.cast(params[:outstanding])

        @compliance_deadlines = paginate(scope)
      end

      def show; end

      def update
        if @compliance_deadline.update(deadline_params)
          render :show
        else
          render_invalid(@compliance_deadline)
        end
      end

      private

      def get_deadline
        @compliance_deadline = ComplianceDeadline.find(params[:id])
      end

      def deadline_params
        params.require(:compliance_deadline).permit(:due_on, :status, :done_on, :note, :purchase_invoice_id)
      end
    end
  end
end
