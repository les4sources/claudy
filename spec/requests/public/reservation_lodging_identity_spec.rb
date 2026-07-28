require "rails_helper"

# Les gîtes ne sont plus anonymes dans la grille de composition (2026-07-29).
#
# On choisissait entre trois NOMS — Hulotte, Chevêche, Grand-Duc — sans savoir
# lequel loge huit personnes et lequel en loge vingt-cinq. `Lodging#summary`
# portait déjà la fourchette et les chambres se comptent : l'information
# existait en base, elle n'était simplement jamais montrée au client.
RSpec.describe "Public::Reservations — identité des gîtes", type: :request do
  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_000, summary: "9 à 16 personnes")
    3.times { |i| l.rooms << Room.create!(name: "Chambre #{i}", level: 1) }
    l
  end
  let!(:cheveche) do
    l = Lodging.create!(name: "La Chevêche", price_night_cents: 24_000, summary: "4 à 8 personnes")
    l.rooms << Room.create!(name: "Chambre unique", level: 1)
    l
  end

  before do
    post "/reservation/sejour", params: {
      reservation: {
        arrival_date: (Date.today + 40).iso8601,
        departure_date: (Date.today + 42).iso8601,
        adults: 2
      }
    }
    get "/reservation/composer"
  end

  it "affiche la capacité et le nombre de chambres de chaque gîte" do
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("9 à 16 personnes · 3 chambres")
    expect(response.body).to include("4 à 8 personnes · 1 chambre")
  end

  it "accorde « chambre » au singulier" do
    expect(response.body).to include("1 chambre<")
    expect(response.body).not_to include("1 chambres")
  end

  it "garde le prix à la nuit à côté" do
    expect(response.body).to match(/dès\s+\d+\s*€\/nuit/)
  end
end
