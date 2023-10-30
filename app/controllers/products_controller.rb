class ProductsController < BaseController
  before_action :get_product, only: [:show, :edit, :update, :destroy]

  breadcrumb "Produits", :products_path, match: :exact

  def index
    @products = ProductDecorator
      .decorate_collection(Product.all.order(name: :asc))
  end

  def show
    @product = ProductDecorator.new(@product)
  end

  def new
    @product = Product.new
  end

  def create
    service = Products::CreateService.new
    if service.run(params)
      redirect_to product_path(service.product),
                  notice: "Super! Le produit '#{service.product.name}' a été ajouté."
    else
      @product = service.product
      set_error_flash(service.product, service.error_message)
      render :new
    end
  end

  def edit
  end

  def update
    service = Products::UpdateService.new(
      product: Product.find(params[:id])
    )
    if service.run(params)
      redirect_to product_path(service.product),
                  notice: "Le produit a été mis à jour."
    else
      @product = service.product
      set_error_flash(service.product, service.error_message)
      render :edit,
             status: :unprocessable_entity,
             alert: service.error_message
    end
  end

  def destroy
    if @product.soft_delete!(validate: false)
      redirect_to products_path,
                  notice: "Le produit '#{@product.name}' a été supprimé."
    else
      flash.now[:alert] = "Une erreur est survenue."
      render :show
    end
  end

  private

  def get_product
    @product = Product.find(params[:id])
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "products"
    )
    @settings_view = true
  end
end
