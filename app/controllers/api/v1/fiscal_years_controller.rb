module Api
  module V1
    # Les exercices comptables (#196).
    #
    # Sans exercice couvrant la date, `Accounting::PostDocument` refuse de
    # comptabiliser — c'est voulu. Reprendre 2022 à 2025 suppose donc de créer
    # ces exercices d'abord.
    #
    # UPSERT sur (entité, date de début). Un exercice CLÔTURÉ ne se modifie plus
    # par l'API : rouvrir un exercice clos est une décision comptable, pas un
    # effet de bord d'un import rejoué.
    class FiscalYearsController < BaseController
      before_action :get_year, only: [:show, :update]

      def index
        scope = FiscalYear.order(:starts_on).includes(:legal_entity)
        scope = scope.where(legal_entity_id: params[:legal_entity_id]) if params[:legal_entity_id].present?
        scope = scope.where(status: params[:status]) if params[:status].present?

        @fiscal_years = paginate(scope)
      end

      def show; end

      def create
        attributes = year_params
        @fiscal_year = FiscalYear.find_or_initialize_by(
          legal_entity_id: attributes[:legal_entity_id], starts_on: attributes[:starts_on]
        )
        @created = @fiscal_year.new_record?
        return render_closed if !@created && @fiscal_year.status == "closed"

        if @fiscal_year.update(attributes)
          render :show, status: @created ? :created : :ok
        else
          render_invalid(@fiscal_year)
        end
      end

      def update
        return render_closed if @fiscal_year.status == "closed"

        if @fiscal_year.update(year_params)
          render :show
        else
          render_invalid(@fiscal_year)
        end
      end

      private

      def get_year
        @fiscal_year = FiscalYear.find(params[:id])
      end

      def render_closed
        render json: {
          error: "conflict",
          message: "Exercice ##{@fiscal_year.id} clôturé : rouvrir un exercice clos est une décision comptable, " \
                   "elle ne passe pas par l'API.",
          fiscal_year_id: @fiscal_year.id
        }, status: :conflict
      end

      def year_params
        params.require(:fiscal_year).permit(:legal_entity_id, :starts_on, :ends_on, :status)
      end
    end
  end
end
