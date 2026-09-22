module Portal
  # « Mes produits » dans l'espace artisan (epic #359, phase 2, décision 7).
  #
  # L'artisan crée ses articles, change leur prix, les désactive. Granularité
  # grossière voulue (un « Savon » à un prix), pas de stock, pas de suppression :
  # un article vendu a des lignes derrière lui.
  #
  # CLOISONNÉ : tout part de `current_portal_consignor.catalog_items`. L'article
  # d'un autre artisan n'existe tout simplement pas ici (404).
  class ConsignorProductsController < Portal::BaseController
    before_action :require_portal_consignor
    before_action :get_product, only: %i[edit update toggle_active]

    def index
      @consignor = current_portal_consignor
      @products = products_scope.includes(:catalog_prices).order(active: :desc, name: :asc)
    end

    def new
      @product = products_scope.new(unit: "piece")
    end

    def create
      @product = products_scope.new
      save_product(:new, "Produit ajouté.")
    end

    def edit
      @price_euros = current_price_euros
    end

    def update
      save_product(:edit, "Produit mis à jour.")
    end

    def toggle_active
      @product.update!(active: !@product.active?)
      notice = @product.active? ? "« #{@product.name} » est de nouveau en vente." : "« #{@product.name} » est retiré de la vente."
      redirect_to portal_consignor_products_path, notice: notice
    end

    private

    def products_scope
      current_portal_consignor.catalog_items.craft
    end

    def get_product
      @product = products_scope.find(params[:id])
    end

    def save_product(template, notice)
      attrs = params.require(:product).permit(:name, :unit, :price_euros)
      service = Consignments::SaveProduct.new(consignor: current_portal_consignor, product: @product)

      if service.run(name: attrs[:name], unit: attrs[:unit], price_euros: attrs[:price_euros])
        redirect_to portal_consignor_products_path, notice: notice
      else
        @price_euros = attrs[:price_euros]
        flash.now[:alert] = service.error_message
        render template, status: :unprocessable_entity
      end
    end

    def current_price_euros
      cents = @product.current_price&.public_price_cents || @product.current_price&.member_price_cents
      cents && format("%.2f", cents / 100.0)
    end
  end
end
