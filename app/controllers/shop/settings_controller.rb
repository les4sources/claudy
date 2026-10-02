module Shop
  # Les coordonnées bancaires des QR des carnets (epic #359, phase 3). Le dépôt
  # est public : l'IBAN de la fondation se règle ici, jamais dans le code.
  class SettingsController < BaseController
    breadcrumb "Carnets de l'épicerie", :shop_settings_path

    before_action :load_revenue_accounts

    def show
      @settings = ShopSetting.current
    end

    def update
      @settings = ShopSetting.current
      if @settings.update(settings_params)
        redirect_to shop_settings_path, notice: "Réglages des carnets enregistrés."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    # Les comptes de produit proposés pour la correspondance carnet → compte
    # (phase 4) : la classe 7, celle des produits.
    def load_revenue_accounts
      @revenue_accounts = GeneralAccount.actives.in_class(7).ordered
    end

    def settings_params
      params.require(:shop_setting).permit(:iban, :bic, :beneficiary_name,
                                           :grocery_account_id, :bread_account_id, :craft_account_id)
    end

    def set_presenters
      @menu_presenter = Components::MenuPresenter.new(active_primary: "settings", active_secondary: "consignors")
      @settings_view = true
    end
  end
end
