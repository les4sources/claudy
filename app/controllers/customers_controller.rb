class CustomersController < BaseController
  before_action :get_customer, only: [:show, :edit, :update]

  breadcrumb "Clients", :customers_path, match: :exact

  def index
    letter = params[:letter].presence || 'A'
    @letters = ('A'..'Z').to_a
    @current_letter = letter

    # On sélectionne tous les clients dont le nom d'affichage commence par la lettre
    @customers = Customer.where(
      "(company_name IS NOT NULL AND company_name != '' AND UPPER(SUBSTR(company_name, 1, 1)) = ?) OR (company_name IS NULL OR company_name = '') AND UPPER(SUBSTR(lastname, 1, 1)) = ?",
      letter, letter
    )

    # On trie par nom d'affichage (company_name si présent, sinon lastname + firstname)
    @customers = @customers.sort_by do |c|
      if c.company_name.present?
        c.company_name.downcase
      else
        "#{c.lastname} #{c.firstname}".downcase
      end
    end

    @customers = CustomerDecorator.decorate_collection(@customers)
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

  def duplicates
    @duplicate_groups = Customer.find_duplicates
  end

  def merge_duplicates
    master_customer_id = params[:master_customer_id]
    duplicate_ids = params[:duplicate_ids] || []
    
    service = Customers::MergeDuplicatesService.new
    if service.run(master_customer_id: master_customer_id, duplicate_ids: duplicate_ids)
      redirect_to duplicates_customers_path, 
                  notice: "#{duplicate_ids.length} client(s) fusionné(s) avec succès."
    else
      redirect_to duplicates_customers_path, 
                  alert: "Erreur lors de la fusion : #{service.error_message}"
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
