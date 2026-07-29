require "rails_helper"

# Photos des gîtes dans le funnel (2026-07-29, photos fournies par Michael).
#
# C'était le dernier grand écart avec un moteur de réservation sérieux : on
# engageait plusieurs centaines d'euros sur un choix fait entre trois NOMS.
# L'étape 2 ouvre maintenant sur trois cartes — couverture, capacité, prix — et
# chacune ouvre la galerie complète du gîte.
#
# Le Grand-Duc étant la Hulotte + la Chevêche réunies, sa galerie est celle des
# deux, ouverte sur la terrasse commune.
#
# La galerie arrive par Turbo Frame, PAS dans le rendu de la page : les 39
# images dans chaque /reservation/composer alourdissaient la page de tout le
# monde pour un panneau que la plupart n'ouvriront jamais.
RSpec.describe "Public::Reservations — galerie des gîtes", type: :request do
  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_000, summary: "9 à 16 personnes")
    l.rooms << Room.create!(name: "Chambre H", level: 1)
    l
  end
  let!(:cheveche) do
    l = Lodging.create!(name: "La Chevêche", price_night_cents: 24_000, summary: "4 à 8 personnes")
    l.rooms << Room.create!(name: "Chambre C", level: 1)
    l
  end
  let!(:grand_duc) do
    Lodging.create!(name: "Le Grand-Duc", price_night_cents: 75_000, summary: "17 à 25 personnes")
  end

  describe "les cartes sur l'étape 2" do
    before do
      post "/reservation/sejour", params: {
        reservation: {
          arrival_date: (Date.today + 45).iso8601,
          departure_date: (Date.today + 47).iso8601,
          adults: 2
        }
      }
      get "/reservation/composer"
    end

    it "rend une carte par gîte, avec sa couverture" do
      expect(response).to have_http_status(:ok)
      expect(response.body.scan(/funnel-lodging-card group/).size).to eq(3)
      %w[cover-hulotte cover-cheveche cover-grand-duc].each { |c| expect(response.body).to include(c) }
    end

    it "annonce le nombre de photos et l'URL de la galerie" do
      expect(response.body).to include("12 photos")  # Hulotte + terrasse
      expect(response.body).to include("8 photos")   # Chevêche + terrasse
      expect(response.body).to include("19 photos")  # Grand-Duc = les deux
      expect(response.body).to include("/reservation/gite/hulotte/photos")
      expect(response.body).to include("/reservation/gite/grand-duc/photos")
    end

    it "ne charge PAS les photos de galerie dans la page" do
      # Le poids de la page ne doit pas grandir avec la taille des galeries :
      # seules les couvertures et les vignettes de grille partent avec le HTML.
      expect(response.body).not_to include("funnel-gallery-img")
      expect(response.body.scan(/<img/).size).to be < 12
    end

    it "reprend la vignette du gîte dans la grille de composition" do
      expect(response.body.scan(/funnel-lodging-thumb/).size).to eq(3)
    end

    it "monte la galerie comme un dialogue accessible" do
      expect(response.body).to include('aria-labelledby="gallery_modal_title"')
      expect(response.body).to include('id="gallery_modal_title"')
      expect(response.body).to include("Fermer la galerie")
      expect(response.body).to include('aria-haspopup="dialog"')
    end
  end

  describe "l'endpoint de galerie" do
    it "sert les photos d'un gîte dans un turbo-frame" do
      get "/reservation/gite/hulotte/photos"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="lodging_gallery"')
      expect(response.body.scan(/funnel-gallery-img/).size).to eq(12)
    end

    it "réunit les deux gîtes pour le Grand-Duc" do
      get "/reservation/gite/grand-duc/photos"

      expect(response.body.scan(/funnel-gallery-img/).size).to eq(19)
    end

    it "décrit chaque photo — jamais d'alt vide" do
      get "/reservation/gite/cheveche/photos"

      images = response.body.scan(/<img[^>]*funnel-gallery-img[^>]*>/)
      expect(images.size).to eq(8)
      images.each do |img|
        alt = img[/alt="([^"]*)"/, 1]
        expect(alt).to be_present, "image sans texte alternatif : #{img[0, 120]}"
        expect(alt.length).to be > 20
      end
    end

    it "diffère le chargement de tout sauf les deux premières" do
      get "/reservation/gite/hulotte/photos"

      images = response.body.scan(/<img[^>]*funnel-gallery-img[^>]*>/)
      expect(images[0]).to include('loading="eager"')
      expect(images.last).to include('loading="lazy"')
    end

    it "ne lève pas sur un slug inconnu — l'URL est publique et devinable" do
      get "/reservation/gite/nawak/photos"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Aucune photo")
      expect(response.body).not_to include("funnel-gallery-img")
    end
  end
end
