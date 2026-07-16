require "rails_helper"

# Issue #15, Phase 3 — mécanisme de locale sur la page client à jeton « espaces ».
# Reprend la même couverture que `locale_switching_spec` (page booking), appliquée
# à `/public/espaces/:token`.
RSpec.describe "Page espaces client — bascule de langue", type: :request do
  let(:space) { Space.create!(name: "Grande Salle", capacity: 20) }
  let(:space_booking) do
    sb = SpaceBooking.create!(firstname: "Alex", lastname: "Durand",
                              from_date: Date.today + 5, to_date: Date.today + 6,
                              status: "confirmed", price_cents: 5_000,
                              payment_method: "bank_transfer", option_kitchenware: true)
    SpaceReservation.create!(space: space, space_booking: sb, date: Date.today + 5, duration: "day")
    sb
  end

  let(:url) { "/public/espaces/#{space_booking.token}" }

  describe "menu de langue" do
    it "rend les 3 langues et conserve le jeton dans chaque lien" do
      get url

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-language-menu")
      %w[fr nl en].each do |code|
        expect(response.body).to include("#{url}?locale=#{code}")
      end
    end
  end

  describe "sélection de la locale" do
    it "sert la page en FR par défaut (lien envoyé au client)" do
      get url
      expect(response.body).to include("Votre réservation")
    end

    it "bascule sur ?locale=nl sans erreur" do
      get "#{url}?locale=nl"
      expect(response).to have_http_status(:ok)
    end

    it "mémorise la langue en session pour les navigations suivantes" do
      get "#{url}?locale=en"
      expect(response).to have_http_status(:ok)

      get url # sans paramètre : la session doit encore porter EN
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('aria-current="true"')
    end

    it "retombe sur le FR (sans 500) pour une locale hors whitelist" do
      get "#{url}?locale=de"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Votre réservation")
    end

    it "renvoie 404 sur un jeton inconnu, quelle que soit la locale" do
      get "/public/espaces/inconnu?locale=nl"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "anti-régression FR (l'extraction ne change pas le texte)" do
    it "affiche les mêmes chaînes témoins qu'avant extraction" do
      get url

      [
        "Votre réservation",
        "Vos informations",
        "Dates de votre réservation",
        "Espace(s)",
        "Votre paiement",
        "Montant de votre réservation"
      ].each do |sentence|
        expect(response.body).to include(sentence)
      end
    end

    it "conserve les liens FAQ et l'adresse de contact" do
      get url

      expect(response.body).to include("les4sources.notion.site")
      expect(response.body).to include("sejours@les4sources.be")
    end
  end
end
