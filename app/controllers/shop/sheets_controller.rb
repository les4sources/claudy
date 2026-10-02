module Shop
  # Les feuilles des carnets de l'épicerie (epic #359, phase 3) : des pages A4
  # imprimées depuis le navigateur, jamais de PDF. Chaque feuille sort à jour —
  # QR du carnet, prix du jour — là où les feuilles photocopiées ne suivaient
  # ni les hausses ni les changements de compte.
  #
  # Une feuille Épicerie ou Boulangerie est numérotée : chaque impression fait
  # avancer le compteur (tant que le QR peut être imprimé).
  class SheetsController < BaseController
    layout "print_sheet"

    def grocery
      numbered_sheet(:grocery, "EPICERIE")
    end

    def bread
      numbered_sheet(:bread, "PAIN")
    end

    # La feuille de prix du mur (décision 12) : prix public du jour, ou prix
    # habitant avec `?audience=member`.
    def grocery_prices
      @audience = params[:audience] == "member" ? "member" : "public"
      @printed_on = Date.current
      items = CatalogItem.active.for_channel("grocery").includes(:catalog_prices).order(:category, :name)
      @groups = items.filter_map { |item| [item, sheet_price(item)] if sheet_price(item) }
                     .group_by { |item, _| item.category.presence || "Divers" }
    end

    private

    def numbered_sheet(kind, communication)
      settings = ShopSetting.current
      @qr = Shop::EpcQrCode.new(communication: communication, settings: settings)
      @settings = settings
      @printed_on = Date.current
      @number = settings.next_sheet_number!(kind) if @qr.configured?
    end

    def sheet_price(item)
      price = item.price_on(@printed_on)
      return nil unless price

      cents = @audience == "member" ? price.member_price_cents : price.public_price_cents
      cents && Money.new(cents, "EUR")
    end

    def set_presenters
      @menu_presenter = Components::MenuPresenter.new(active_primary: "settings")
    end
  end
end
