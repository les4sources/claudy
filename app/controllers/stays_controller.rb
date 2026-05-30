class StaysController < BaseController
  before_action :set_accounting_view, only: :show

  # Rendu sans layout : le fragment HTML est injecté dans la modale de détails
  # par le contrôleur Stimulus stay-details (fetch + innerHTML). [tranche 1]
  def show
    @stay = Stay.includes(stay_items: :bookable, customer: []).find(params[:id]).decorate
    render layout: false
  end

  # Vue admin Pôle Accueil — Stays récents filtrables par canal d'attribution
  # (source), pour observer la transition Tally → /reservation (AC-T2-23/24).
  # Protégée Devise via BaseController (préserve ISC-3).
  def recent
    @source = params[:source].presence
    @sources = Stay::SOURCES
    @stays = Stay.from_source(@source).recent.includes(:customer).limit(100).decorate
  end

  private

  def set_accounting_view
    @accounting_view = true
  end

  def set_presenters; end
end
