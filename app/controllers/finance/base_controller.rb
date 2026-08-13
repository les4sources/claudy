module Finance
  # Socle de la section Finances (issue #155). Pose `@finance_view`, qui allume
  # l'entrée primaire « Finances » et sa sous-navigation, exactement comme
  # `@settings_view` le fait pour Paramètres.
  class BaseController < ::BaseController
    breadcrumb "Finances", :finance_accounts_path, match: :exact

    private

    def set_presenters
      @menu_presenter = Components::MenuPresenter.new(
        active_primary: "finance",
        active_secondary: finance_secondary
      )
      @finance_view = true
    end

    def finance_secondary = "accounts"
  end
end
