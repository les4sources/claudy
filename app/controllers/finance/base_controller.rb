module Finance
  # Socle de la section « Comptes » (issue #155), nommée « Finances » jusqu'au
  # 2026-09-20 : le mot désignait un domaine, pas ce qu'on vient y faire — lire
  # son compte. Pose `@finance_view`, qui allume l'entrée primaire et sa
  # sous-navigation, exactement comme `@settings_view` le fait pour Paramètres.
  class BaseController < ::BaseController
    breadcrumb "Comptes", :finance_accounts_path, match: :exact

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
