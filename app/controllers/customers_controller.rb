class CustomersController < BaseController
  
  def index  
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

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "customers",
      controller_name: controller_name,
      action_name: action_name,
      view_context: view_context
    )
  end

end
