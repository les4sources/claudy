module Api
  module V1
    # Les règles d'affectation (#183), pilotables par un agent.
    #
    # Une règle PROPOSE, elle ne décide jamais — l'API n'y change rien. Elle
    # ouvre la configuration, pas l'acceptation : poser une règle ne
    # comptabilise pas un centime, et l'acceptation des suggestions reste au
    # navigateur, devant un humain qui voit combien de lignes il touche.
    #
    # POST est un UPSERT sur le LIBELLÉ. Un agent qui rejoue sa passe ne doit
    # pas accumuler six « Bar — virements » qui se disputent la même ligne :
    # l'ordre deviendrait indéchiffrable et la première règle gagnerait au
    # hasard de l'identifiant.
    class AllocationRulesController < BaseController
      # Le message d'erreur parle la langue de l'agent : « Compte général
      # inconnu : 999999 » se corrige tout seul, « general_account_id
      # introuvable » demande de lire le code.
      LIBELLES = {
        general_account_id: "Compte général inconnu",
        analytic_account_id: "Axe analytique inconnu",
        team_id: "Pôle inconnu",
        legal_entity_id: "Entité inconnue"
      }.freeze

      before_action :get_rule, only: [:show, :update, :destroy]

      def index
        scope = AllocationRule.ordered.includes(:general_account, :analytic_account, :team, :legal_entity)
        scope = scope.where(direction: params[:direction]) if params[:direction].present?

        active = ActiveModel::Type::Boolean.new.cast(params[:active])
        scope = active ? scope.actives : scope.where(active: false) unless active.nil?

        @allocation_rules = paginate(scope)
      end

      def show; end

      def create
        attributes = rule_params.merge(resolved_associations)
        return if performed?

        @allocation_rule = AllocationRule.find_or_initialize_by(label: attributes[:label])
        @created = @allocation_rule.new_record?

        if @allocation_rule.update(attributes)
          render :show, status: @created ? :created : :ok
        else
          render_invalid(@allocation_rule)
        end
      end

      def update
        attributes = rule_params.merge(resolved_associations)
        return if performed?

        if @allocation_rule.update(attributes)
          render :show
        else
          render_invalid(@allocation_rule)
        end
      end

      def destroy
        @allocation_rule.destroy
        head :no_content
      end

      private

      def get_rule
        @allocation_rule = AllocationRule.find(params[:id])
      end

      def rule_params
        params.require(:allocation_rule).permit(
          :label, :position, :confidence, :active, :direction,
          :counterparty_iban, :counterparty_name_contains, :communication_contains,
          :transaction_code, :min_amount_cents, :max_amount_cents,
          :general_account_id, :analytic_account_id, :team_id, :legal_entity_id, :event_id
        )
      end

      # Un agent connaît un compte par son CODE et un pôle par son NOM — ce sont
      # les seules clés qui survivent à une restauration de base. Les
      # identifiants techniques restent acceptés pour les liens rendus par les
      # autres vues.
      def resolved_associations
        payload = params.require(:allocation_rule)
        resolved = {}

        resolve(payload[:general_account_code], resolved, :general_account_id) do |code|
          GeneralAccount.find_by(code: code)
        end
        resolve(payload[:analytic_account_code], resolved, :analytic_account_id) do |code|
          AnalyticAccount.find_by(code: code)
        end
        resolve(payload[:team_name], resolved, :team_id) do |name|
          Team.find_by(name: name)
        end
        resolve(payload[:legal_entity_name], resolved, :legal_entity_id) do |name|
          LegalEntity.find_by(name: name)
        end

        resolved
      end

      def resolve(value, resolved, key)
        return if value.blank? || performed?

        record = yield(value)
        if record.nil?
          return render json: { error: "unprocessable_entity",
                                message: "#{LIBELLES.fetch(key)} : #{value}." },
                        status: :unprocessable_entity
        end

        resolved[key] = record.id
      end
    end
  end
end
