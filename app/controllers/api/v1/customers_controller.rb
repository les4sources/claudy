module Api
  module V1
    # Read-only agent surface for Customer (PRD §3.1, AC-27/30/31). Soft-deleted
    # customers are excluded by the model default scope, so a soft-deleted id
    # surfaces as 404 via the BaseController rescue (AC-30). Notes are internal
    # only and never serialized (decision §11.7).
    class CustomersController < BaseController
      def index
        scope = Customer.all
        scope = scope.search(params[:q]) if params[:q].present?
        scope = scope.where(customer_type: params[:customer_type]) if params[:customer_type].present?
        @customers = paginate(scope.order(created_at: :desc))
      end

      def show
        @customer = Customer.find(params[:id])
      end
    end
  end
end
