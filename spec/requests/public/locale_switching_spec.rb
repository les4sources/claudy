require "rails_helper"

# Issue #15, Phase 1 — mécanisme de locale des pages client à jeton.
RSpec.describe "Pages client — bascule de langue", type: :request do
  let(:booking) do
    Booking.create!(firstname: "Alex", lastname: "Durand", from_date: Date.today + 10,
                    to_date: Date.today + 12, adults: 2, children: 1, babies: 0, status: "confirmed",
                    booking_type: "lodging", price_cents: 48_500)
  end

  let(:url) { "/public/reservation/#{booking.token}" }

  describe "menu de langue" do
    it "rend les 3 langues et conserve le jeton dans chaque lien" do
      get url

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-language-menu')
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
      expect(response.body).to match(/aria-current="true"[^>]*>\s*EN|EN\s*<\/a>/)
    end

    it "retombe sur le FR (sans 500) pour une locale hors whitelist" do
      get "#{url}?locale=de"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Votre réservation")
    end

    it "retombe sur le FR après une locale invalide, même si la session portait NL" do
      get "#{url}?locale=nl"
      get "#{url}?locale=klingon"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Votre réservation")
    end

    it "renvoie 404 sur un jeton inconnu, quelle que soit la locale" do
      get "/public/reservation/inconnu?locale=nl"
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
        "Hébergement(s)",
        "Personnes enregistrées",
        "Votre arrivée",
        "À emporter avec vous",
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
