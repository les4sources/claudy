module Kitchen
  # Produits du buffet (epic #219, phase 6) : ce que `Kitchen::ShoppingList`
  # lit pour calculer une liste de courses. Ce sont des réglages, comme les
  # tarifs — suppression réelle, jamais de soft-deletion.
  class ProductsController < BaseController
    before_action :set_product, only: [:edit, :update, :destroy]

    breadcrumb "Produits du buffet", :kitchen_products_path, match: :exact

    def index
      @products = KitchenProduct.ordered
    end

    def new
      @product = KitchenProduct.new(active: true)
    end

    def create
      @product = KitchenProduct.new(product_params)

      if @product.save
        redirect_to kitchen_products_path, notice: "Le produit « #{@product.name} » a été créé."
      else
        flash.now[:alert] = @product.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @product.update(product_params)
        redirect_to kitchen_products_path, notice: "Le produit a été mis à jour."
      else
        flash.now[:alert] = @product.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      name = @product.name
      @product.destroy
      redirect_to kitchen_products_path, notice: "Le produit « #{name} » a été supprimé."
    end

    private

    def set_product
      @product = KitchenProduct.find(params[:id])
    end

    def product_params
      params.require(:kitchen_product)
            .permit(:name, :unit, :note, :position, :active, quantities: KitchenProduct::KINDS)
    end

    def set_presenters
      @settings_view = true
    end
  end
end
