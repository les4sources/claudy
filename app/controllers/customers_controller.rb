class CustomersController < BaseController
  before_action :set_accounting_view
  before_action :get_customer, only: [:show, :edit, :update, :merge, :merge_preview, :merge_commit, :reassign]

  breadcrumb "Clients", :customers_path, match: :exact

  def index
    scope = Customer.search(params[:q]).order(created_at: :desc)
    @customers = CustomerDecorator.decorate_collection(scope.paginate(page: params[:page], per_page: 30))
  end

  # Autocomplete JSON pour la re-ventilation (recherche dynamique de client cible).
  def search
    customers = Customer.search(params[:q]).order(:first_name, :last_name, :email).limit(10)
    render json: customers.map { |c| { id: c.id, name: c.name, email: c.email } }
  end

  def show
    breadcrumb @customer.display_name, customer_path(@customer)
    # Cibles possibles pour la re-ventilation des séjours (tout client sauf celui-ci).
    @reassign_targets = Customer.where.not(id: @customer.id).order(:first_name, :last_name, :email)
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

  # Re-ventilation : transfère les séjours cochés du client courant (souvent le
  # fourre-tout) vers une cible — soit un client existant (target_id), soit un
  # nouveau client créé à la volée (new_customer). S'appuie sur le même
  # MergeService que la fusion de doublons (AC-50/52/53/54).
  def reassign
    stay_ids = Array(params[:stay_ids]).reject(&:blank?)
    if stay_ids.empty?
      redirect_to customer_path(@customer), notice: "Aucun séjour sélectionné."
      return
    end

    target, error = resolve_reassign_target
    if target.nil?
      redirect_to customer_path(@customer), alert: error
      return
    end

    service = Customers::MergeService.new(source: @customer, target: target)
    if service.run(stay_ids: stay_ids)
      redirect_to customer_path(@customer),
                  notice: "#{service.stays_moved} séjour(s) assigné(s) à #{target.display_name}."
    else
      redirect_to customer_path(@customer), alert: service.error_message
    end
  end

  private

  # Returns [target_customer, nil] on success or [nil, error_message] on failure.
  def resolve_reassign_target
    if params[:target_id].present?
      [Customer.find(params[:target_id]), nil]
    elsif params.dig(:new_customer, :email).present?
      customer = Customer.new(new_customer_params)
      if customer.save
        [customer, nil]
      else
        [nil, customer.errors.full_messages.join(", ")]
      end
    else
      [nil, "Choisissez un client existant ou renseignez un nouveau client."]
    end
  end

  def new_customer_params
    params.require(:new_customer).permit(
      :first_name, :last_name, :email, :phone, :customer_type, :organization_name, :language
    )
  end

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

  # BaseController#render calls set_presenters on every render; this controller
  # has no dedicated presenter, so it is a no-op (same pattern as other
  # presenter-less controllers, e.g. BookingPricesController).
  def set_presenters; end
end
