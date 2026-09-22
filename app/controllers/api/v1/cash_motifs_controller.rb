module Api
  module V1
    # Les motifs de caisse (epic #243), pilotables par un agent.
    #
    # LE MOTIF EST L'AFFECTATION : il porte le compte général, le pôle et
    # l'entité, et la ligne de caisse en prend une COPIE au moment de la saisie.
    # Réaffecter un motif par l'API ne réécrit donc aucune ligne déjà saisie —
    # c'est ce qui rend l'écriture ici sans danger pour un exercice en cours.
    #
    # POST est un UPSERT sur le LIBELLÉ, que le modèle impose déjà unique.
    class CashMotifsController < BaseController
      # Le message d'erreur parle la langue de l'agent : « Compte général
      # inconnu : 999999 » se corrige tout seul, « general_account_id
      # introuvable » demande de lire le code.
      LIBELLES = {
        general_account_id: "Compte général inconnu",
        analytic_account_id: "Axe analytique inconnu",
        team_id: "Pôle inconnu",
        legal_entity_id: "Entité inconnue"
      }.freeze

      before_action :get_motif, only: [:show, :update]

      def index
        scope = CashMotif.ordered.includes(:general_account, :team, :legal_entity)
        scope = scope.for_direction(params[:direction]) if params[:direction].present?

        active = ActiveModel::Type::Boolean.new.cast(params[:active])
        scope = active ? scope.actives : scope.where(active: false) unless active.nil?

        @cash_motifs = paginate(scope)
      end

      def show; end

      def create
        attributes = motif_params.merge(resolved_associations)
        return if performed?

        @cash_motif = CashMotif.find_or_initialize_by(label: attributes[:label])
        @created = @cash_motif.new_record?

        if @cash_motif.update(attributes)
          render :show, status: @created ? :created : :ok
        else
          render_invalid(@cash_motif)
        end
      end

      def update
        attributes = motif_params.merge(resolved_associations)
        return if performed?

        if @cash_motif.update(attributes)
          render :show
        else
          render_invalid(@cash_motif)
        end
      end

      private

      def get_motif
        @cash_motif = CashMotif.find_by(label: params[:id]) || CashMotif.find(params[:id])
      end

      def motif_params
        params.require(:cash_motif).permit(:label, :direction, :position, :active,
                                           :general_account_id, :team_id, :legal_entity_id)
      end

      def resolved_associations
        payload = params.require(:cash_motif)
        resolved = {}

        resolve(payload[:general_account_code], resolved, :general_account_id) do |code|
          GeneralAccount.find_by(code: code)
        end
        resolve(payload[:team_name], resolved, :team_id) { |name| Team.find_by(name: name) }
        resolve(payload[:legal_entity_name], resolved, :legal_entity_id) { |name| LegalEntity.find_by(name: name) }

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
