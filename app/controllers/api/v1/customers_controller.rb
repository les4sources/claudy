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

      def update
        @customer = Customer.find(params[:id])
        if @customer.update(customer_params)
          render :show
        else
          render_invalid(@customer)
        end
      end

      def destroy
        Customer.find(params[:id]).soft_delete!
        head :no_content
      end

      private

      # `notes`, `stripe_customer_id` are intentionally not writable here (internal
      # / provider-managed, §11.7).
      def customer_params
        params.require(:customer).permit(
          :first_name, :last_name, :email, :phone, :customer_type, :organization_name,
          :vat_number, :peppol_id, :address_line, :address_zip, :address_city,
          :address_country, :language, :marketing_consent, :nps_eligible, :human_id
        )
      end
    end
  end
end
