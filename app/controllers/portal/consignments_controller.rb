module Portal
  # L'espace artisan en dépôt-vente (epic #359, décision 8).
  #
  # Phase 1 ouvre la PORTE et rien d'autre : l'artisan se connecte par code
  # email et voit son contrat. « Mes produits », l'encodage d'une feuille et
  # l'impression arrivent aux phases 2 et 3 — ils atterriront ici.
  #
  # Le scope part TOUJOURS de `current_portal_consignor` : aucun identifiant
  # d'artisan ne circule dans l'URL, il n'y a donc rien à forger.
  class ConsignmentsController < Portal::BaseController
    before_action :require_portal_consignor

    def show
      @consignor = current_portal_consignor
      @last_report = @consignor.consignment_reports.ordered.first
    end
  end
end
