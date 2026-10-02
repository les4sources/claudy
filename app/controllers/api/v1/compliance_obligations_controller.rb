module Api
  module V1
    # Les obligations de l'échéancier comptable, pilotables par un agent.
    #
    # POST est un UPSERT sur le couple (titre, entité), que le modèle impose
    # déjà unique : rejouer une reprise ne crée pas de doublon. Chaque écriture
    # régénère les échéances de la règle — on lit dans la réponse ce qu'on vient
    # de décrire.
    class ComplianceObligationsController < BaseController
      before_action :get_obligation, only: [:show, :update]

      def index
        scope = ComplianceObligation.ordered.includes(:legal_entity, :responsible_user)
        scope = scope.where(legal_entity: entity_param) if params[:legal_entity_name].present?

        @compliance_obligations = paginate(scope)
      end

      def show; end

      def create
        attributes = resolved_attributes
        return if performed?

        @compliance_obligation = ComplianceObligation.find_or_initialize_by(
          legal_entity_id: attributes[:legal_entity_id], title: attributes[:title]
        )
        @created = @compliance_obligation.new_record?
        save_and_render(attributes, status: @created ? :created : :ok)
      end

      def update
        attributes = resolved_attributes
        return if performed?

        save_and_render(attributes, status: :ok)
      end

      private

      def get_obligation
        @compliance_obligation = ComplianceObligation.find(params[:id])
      end

      def save_and_render(attributes, status:)
        if @compliance_obligation.update(attributes)
          ComplianceDeadlines::Generate.new(obligations: ComplianceObligation.where(id: @compliance_obligation.id)).run!
          @compliance_obligation.compliance_deadlines.reset
          render :show, status: status
        else
          render_invalid(@compliance_obligation)
        end
      end

      def entity_param
        LegalEntity.find_by(name: params[:legal_entity_name])
      end

      def resolved_attributes
        payload = params.require(:compliance_obligation)
        attributes = payload.permit(:title, :legal_entity_id, :frequency, :first_due_on, :ends_on, :covers,
                                    :payment, :responsible_user_id, :instructions, :active).to_h.symbolize_keys

        if payload[:legal_entity_name].present?
          entity = LegalEntity.find_by(name: payload[:legal_entity_name])
          return unprocessable("Entité inconnue : #{payload[:legal_entity_name]}.") if entity.nil?

          attributes[:legal_entity_id] = entity.id
        end

        if payload[:responsible_email].present?
          user = User.find_by("LOWER(email) = ?", payload[:responsible_email].to_s.downcase)
          return unprocessable("Utilisateur inconnu : #{payload[:responsible_email]}.") if user.nil?

          attributes[:responsible_user_id] = user.id
        end

        attributes
      end

      def unprocessable(message)
        render json: { error: "unprocessable_entity", message: message }, status: :unprocessable_entity
      end
    end
  end
end
