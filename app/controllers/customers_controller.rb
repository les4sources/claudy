class CustomersController < BaseController
  before_action :set_accounting_view
  before_action :get_customer, only: [:show, :edit, :update, :merge, :merge_preview, :merge_commit]

  breadcrumb "Clients", :customers_path, match: :exact

  def index
    scope = Customer.search(params[:q]).order(created_at: :desc)
    @customers = CustomerDecorator.decorate_collection(scope.paginate(page: params[:page], per_page: 30))
  end

  def show
    breadcrumb @customer.display_name, customer_path(@customer)
    @customer = CustomerDecorator.decorate(@customer)
  end

  def edit
    breadcrumb @customer.display_name, customer_path(@customer)
    breadcrumb "Modifier", edit_customer_path(@customer)
  end

  def update
    if @customer.update(customer_params)
      redirect_to customer_path(@customer), notice: "Le client a été mis à jour."
    else
      set_error_flash(@customer, @customer.errors.full_messages.join(", "))
      render :edit, status: :unprocessable_entity
    end
  end

  # Step 1 of the merge flow: pick the target customer to merge the source into.
  def merge
    breadcrumb @customer.display_name, customer_path(@customer)
    breadcrumb "Fusionner", merge_customer_path(@customer)
    @candidates = Customer.where.not(id: @customer.id).search(params[:q]).order(created_at: :desc).limit(30)
  end

  # Step 2: confirmation screen listing what will be transferred before commit.
  def merge_preview
    @target = Customer.find(params[:target_id])
    if @target.id == @customer.id
      redirect_to merge_customer_path(@customer), alert: "Le client cible doit être différent de la source."
      return
    end
    @source = @customer
  end

  # Step 3: execute the merge via the service.
  def merge_commit
    target = Customer.find(params[:target_id])
    service = Customers::MergeService.new(source: @customer, target: target)
    if service.run
      redirect_to customer_path(target),
                  notice: "#{service.stays_moved} séjour(s) transféré(s). Le client source a été fusionné."
    else
      redirect_to merge_customer_path(@customer), alert: service.error_message
    end
  end

  private

  def get_customer
    @customer = Customer.find(params[:id])
  end

  def customer_params
    params.require(:customer).permit(
      :first_name, :last_name, :email, :phone, :customer_type, :organization_name,
      :vat_number, :peppol_id, :address_line, :address_zip, :address_city,
      :address_country, :language, :marketing_consent, :nps_eligible, :notes
    )
  end

  def set_accounting_view
    @accounting_view = true
  end
end
