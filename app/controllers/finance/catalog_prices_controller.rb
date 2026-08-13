module Finance
  # Paliers de prix datés d'un article (issue #157).
  #
  # Créer un palier au 1er septembre ne change pas le prix résolu au 31 août :
  # le palier précédent est simplement clos la veille. C'est ce qui protège les
  # décomptes déjà émis et la reprise de l'historique.
  class CatalogPricesController < Finance::BaseController
    before_action :get_item
    before_action :get_price, only: [:destroy]

    def create
      @price = @item.catalog_prices.new(price_params)
      close_previous_period

      if @price.save
        redirect_to finance_catalog_path(@item), notice: "Le palier de prix a été ajouté."
      else
        redirect_to finance_catalog_path(@item), alert: @price.errors.full_messages.to_sentence
      end
    end

    def destroy
      @price.destroy!
      reopen_last_period
      redirect_to finance_catalog_path(@item), notice: "Le palier a été supprimé."
    end

    private

    def get_item
      @item = CatalogItem.find(params[:catalog_id])
    end

    def get_price
      @price = @item.catalog_prices.find(params[:id])
    end

    # Le palier en vigueur la veille du nouveau est clos à cette veille. Sans
    # ça, les deux se chevaucheraient et `price_on` n'aurait plus de réponse
    # unique — la validation du modèle refuserait d'ailleurs l'enregistrement.
    def close_previous_period
      return if @price.active_from.blank?

      previous = @item.catalog_prices.covering(@price.active_from).first
      previous&.update!(active_until: @price.active_from - 1.day)
    end

    # Supprimer le dernier palier rouvre celui qui le précédait, sinon l'article
    # se retrouverait sans prix courant alors qu'il en avait un.
    def reopen_last_period
      last = @item.catalog_prices.most_recent_first.first
      last&.update!(active_until: nil)
    end

    def price_params
      params.require(:catalog_price).permit(:active_from, :note)
            .merge(
              purchase_price_cents: cents_from(params.dig(:catalog_price, :purchase_price)),
              reference_price_cents: cents_from(params.dig(:catalog_price, :reference_price)),
              member_price_cents: cents_from(params.dig(:catalog_price, :member_price)),
              public_price_cents: cents_from(params.dig(:catalog_price, :public_price))
            )
    end

    # Saisie en euros, virgule tolérée. Une valeur vide reste nil : un article
    # peut n'avoir ni prix d'achat (don, récupération) ni prix public.
    def cents_from(raw)
      value = raw.to_s.strip.tr(",", ".")
      return nil unless value.match?(/\A\d+(\.\d+)?\z/)

      (value.to_f * 100).round
    end

    def finance_secondary = "catalog"
  end
end
