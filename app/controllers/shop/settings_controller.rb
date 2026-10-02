module Shop
  # Les coordonnées bancaires des QR des carnets (epic #359, phase 3). Le dépôt
  # est public : l'IBAN de la fondation se règle ici, jamais dans le code.
  class SettingsController < BaseController
    breadcrumb "Carnets de l'épicerie", :shop_settings_path

    def show
      @settings = ShopSetting.current
    end

    def update
      @settings = ShopSetting.current
      if @settings.update(settings_params)
        redirect_to shop_settings_path, notice: "Coordonnées bancaires enregistrées."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def settings_params
      params.require(:shop_setting).permit(:iban, :bic, :beneficiary_name)
    end

    def set_presenters
      @menu_presenter = Components::MenuPresenter.new(active_primary: "settings", active_secondary: "consignors")
      @settings_view = true
    end
  end
end
