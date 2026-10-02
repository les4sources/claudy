module Portal
  # « Mes virements » dans l'espace artisan (epic #359, phase 4) : les virements
  # « ARTISANAT <PRÉNOM> » que la fondation a reçus pour lui, rattachés au
  # rapprochement bancaire. Lecture seule.
  #
  # Date, montant, communication — et rien d'autre : le nom et l'IBAN du client
  # qui a payé ne regardent pas l'artisan.
  class ConsignorTransfersController < Portal::BaseController
    before_action :require_portal_consignor

    def index
      @consignor = current_portal_consignor
      @transfers = @consignor.cash_entries.where.not(status: "excluded").ordered.to_a
      @months = @transfers.group_by { |transfer| transfer.entry_date.beginning_of_month }
    end
  end
end
