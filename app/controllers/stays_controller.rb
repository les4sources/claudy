class StaysController < ApplicationController
  def show
    @stay = Stay.find(params[:id]).decorate
    @reservations_by_date = nil
  end

  # Vue admin Pôle Accueil — Stays récents filtrables par canal d'attribution
  # (source), pour observer la transition Tally → /reservation (AC-T2-23/24).
  def recent
    @source = params[:source].presence
    @sources = Stay::SOURCES
    @stays = Stay.from_source(@source).recent.includes(:customer).limit(100).decorate
  end
end
