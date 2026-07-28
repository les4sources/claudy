require "rails_helper"

# Garde-fou « panier vide » de l'étape 2 du funnel /reservation.
#
# Avant : le bouton « Continuer vers les activités » restait actif à 0,00 €. On
# pouvait traverser les activités puis les coordonnées et déposer une demande
# sans la moindre nuit d'hébergement, ni emplacement, ni salle — un lead vide
# côté équipe, et côté client un « séjour » qui ne contient rien.
#
# L'état du bouton suit le devis : il est rendu par un partial que le Turbo
# Stream de /reservation/devis remplace au même titre que le total collant, pour
# qu'il se débloque dès la première sélection sans recharger la page.
RSpec.describe "Public::Reservations — CTA de composition", type: :request do
  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre 1", level: 1)
    l
  end

  let(:arrival)   { (Date.today + 60).iso8601 }
  let(:departure) { (Date.today + 62).iso8601 }

  def pose_les_dates
    post "/reservation/sejour", params: {
      reservation: { arrival_date: arrival, departure_date: departure, adults: 2 }
    }
  end

  describe "panier vide" do
    it "bloque le bouton et dit pourquoi" do
      pose_les_dates
      get "/reservation/composer"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="compose_cta"')
      expect(response.body).to match(/<button[^>]*disabled[^>]*>(?:(?!<\/button>).)*Continuer vers les activités/m)
      expect(response.body).to include("Choisissez au moins une nuit d'hébergement")
    end

    it "relie l'explication au bouton pour l'assistance technique" do
      pose_les_dates
      get "/reservation/composer"

      expect(response.body).to include('aria-describedby="compose_cta_reason"')
      expect(response.body).to include('id="compose_cta_reason"')
    end
  end

  describe "dès qu'une nuit est choisie" do
    it "débloque le bouton" do
      pose_les_dates
      post "/reservation/devis", params: {
        reservation: {
          arrival_date: arrival, departure_date: departure,
          lodging_night_ids: [hulotte.id.to_s, "", ""]
        }
      }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      # Le stream doit porter le CTA, sinon son état resterait figé au premier rendu.
      expect(response.body).to include('target="compose_cta"')
      cta = response.body[/<div id="compose_cta".*?<\/div>/m] || response.body
      expect(cta).not_to include("disabled")
      expect(response.body).not_to include("Choisissez au moins une nuit d'hébergement")
    end
  end
end
