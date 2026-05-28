module Api
  module V1
    # Read-only agent surface for Stay (PRD §3.2, AC-28/30/31). A stay exposes
    # its polymorphic items and their concrete types. Soft-deleted stays are
    # excluded by the model default scope (AC-30).
    class StaysController < BaseController
      def index
        scope = Stay.all
        scope = scope.where(customer_id: params[:customer_id]) if params[:customer_id].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        @stays = paginate(scope.includes(:customer, stay_items: :bookable).order(arrival_date: :desc))
      end

      def show
        @stay = Stay.includes(:customer, stay_items: :bookable).find(params[:id])
      end
    end
  end
end
