module Finance
  # Socle de la section Comptabilité (Michael, 2026-08-19). Tenir les journaux
  # et lire son compte de sourcier sont deux métiers : la première appartient à
  # la trésorière, la seconde à chaque habitant. Les deux partagent l'espace de
  # noms `Finance::` et les URLs `/finance/...` — mais plus la même entrée de
  # menu. Hériter d'ici, c'est basculer d'une section à l'autre : rien d'autre
  # n'est à déclarer.
  class AccountingBaseController < ::BaseController
    breadcrumb "Comptabilité", :finance_accounting_path, match: :exact

    private

    def set_presenters
      @menu_presenter = Components::MenuPresenter.new(
        active_primary: "accounting",
        active_secondary: accounting_secondary
      )
      @accounting_view = true
    end

    def accounting_secondary = "accounting"
  end
end
