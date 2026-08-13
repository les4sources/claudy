module Finance
  # Catalogue du bar et du cellier (issue #157).
  #
  # L'écran d'impression sert deux publics : la liste SOURCIER, affichée au bar,
  # ne montre jamais le prix d'achat — c'est le seul chiffre qui n'a rien à
  # faire sur un mur.
  class CatalogController < Finance::BaseController
    before_action :get_item, only: [:show, :edit, :update, :destroy]

    breadcrumb "Catalogue", :finance_catalog_index_path, match: :exact

    def index
      @channel = params[:channel].presence
      @term = params[:q].presence
      @items = CatalogItem.ordered
                          .for_channel(@channel)
                          .matching(@term)
                          .includes(:catalog_prices)
      @items = CatalogItemDecorator.decorate_collection(@items)
    end

    def show
      breadcrumb @item.name, finance_catalog_path(@item), match: :exact

      @prices = @item.catalog_prices.most_recent_first
      @price = CatalogPrice.new(active_from: Date.current)
    end

    def new
      @item = CatalogItem.new(channel: params[:channel].presence || "bar")
    end

    def create
      @item = CatalogItem.new(item_params)

      if @item.save
        redirect_to finance_catalog_path(@item), notice: "L'article « #{@item.name} » a été créé."
      else
        flash.now[:alert] = @item.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @item.update(item_params)
        redirect_to finance_catalog_path(@item), notice: "L'article a été mis à jour."
      else
        flash.now[:alert] = @item.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @item.soft_delete!(validate: false)
      redirect_to finance_catalog_index_path, notice: "L'article « #{@item.name} » a été retiré."
    end

    # Listes imprimables. `audience=member` est affichée au bar : elle ne porte
    # ni prix d'achat ni prix de référence.
    def print
      @audience = params[:audience] == "public" ? "public" : "member"
      @channel = params[:channel].presence
      @items = CatalogItem.ordered.active.for_channel(@channel).includes(:catalog_prices)
      @items = CatalogItemDecorator.decorate_collection(@items)

      render layout: "print"
    end

    # Prérempli du formulaire de palier : le générateur PROPOSE, l'humain
    # décide. Répond en JSON pour que la saisie du prix d'achat mette à jour les
    # champs sans recharger la page.
    def suggest_price
      proposal = Catalog::BuildPrice.new(
        channel: params[:channel],
        purchase_price_cents: cents_from(params[:purchase]),
        reference_price_cents: cents_from(params[:reference]),
        on: params[:on].presence&.to_date || Date.current
      ).run!

      render json: {
        member_price: proposal.member_price_cents&./(100.0),
        public_price: proposal.public_price_cents&./(100.0)
      }
    end

    private

    def get_item
      @item = CatalogItem.find(params[:id])
    end

    def cents_from(raw)
      value = raw.to_s.strip.tr(",", ".")
      return nil unless value.match?(/\A\d+(\.\d+)?\z/)

      (value.to_f * 100).round
    end

    def item_params
      params.require(:catalog_item).permit(:name, :channel, :category, :unit, :reference, :active)
    end

    def finance_secondary = "catalog"
  end
end
