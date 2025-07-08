class CustomersController < BaseController
  before_action :get_customer, only: [:show, :edit, :update]

  breadcrumb "Clients", :customers_path, match: :exact

  def index
    @customers = CustomerDecorator.decorate_collection(Customer.all.order(:lastname, :firstname))
  end

  def show
    @customer = @customer.decorate
  end

  def new
    @customer = Customer.new
  end

  def create
    service = Customers::CreateService.new
    if service.run(params)
      redirect_to customer_path(service.customer),
                  notice: "Super! Le client a été ajouté."
    else
      @customer = service.customer
      set_error_flash(service.customer, service.error_message)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Add breadcrumb for this specific customer
    breadcrumb @customer.decorate.display_name, customer_path(@customer)
  end

  def update
    service = Customers::UpdateService.new(customer: @customer)
    if service.run(params)
      redirect_to @customer, notice: "Les informations du client ont été mises à jour."
    else
      @customer = service.customer
      set_error_flash(service.customer, service.error_message)
      render :edit, 
             status: :unprocessable_entity,
             alert: service.error_message
    end
  end

  def lookup
    customer = Customer.find_by(email: params[:email])
    
    if customer
      render json: {
        found: true,
        firstname: customer.firstname,
        lastname: customer.lastname,
        phone: customer.phone
      }
    else
      render json: { found: false }
    end
  end

  private

  def get_customer
    @customer = Customer.find(params[:id])
  end

  def customer_params
    params.require(:customer).permit(
      :firstname, :lastname, :phone, :email, :notes,
      :company_name, :vat_number,
      :street, :number, :box, :postcode, :city, :country
    )
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "customers",
      controller_name: controller_name,
      action_name: action_name,
      view_context: view_context
    )
  end

end
