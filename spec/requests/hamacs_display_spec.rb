require "rails_helper"

# Issue #138 — un séjour avec hamacs les MONTRE : ligne dédiée dans la modale
# séjour, chip 🛌 sur le bloc du calendrier, et compte dans la nuitée (💤).
RSpec.describe "Hamacs — affichage modale + calendrier (issue #138)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-hamacs@les4sources.be", password: "password123") }
  before { sign_in user }

  let(:arrival)   { Date.today.next_occurring(:friday) }
  let(:departure) { arrival + 2 }

  # Séjour hamacs SEULS : rien d'autre ne peut expliquer la chip ni la nuitée.
  let!(:stay) do
    draft = Reservations::Draft.new(
      arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: "camille-hamac@example.com", phone: "+32470112233",
      per_night_resources: { "hamac_double" => %w[1 1] }
    )
    builder = Reservations::Builder.new(draft: draft, admin: true, status: "confirmed")
    builder.run!
    builder.stay
  end

  it "affiche la ligne hamacs dans la modale séjour" do
    get stay_path(stay)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Location de hamacs")
    expect(response.body).to include("Hamac double × 1")
  end

  it "affiche la chip 🛌 et la nuitée 💤 sur le bloc du calendrier" do
    get "/", params: { date: arrival.iso8601 }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("🛌 Hamac double × 1")
    expect(response.body).to include("Nuitée sur place")
  end

  it "compte les hamacs dans le résumé de composition du séjour" do
    expect(stay.decorate.composition_summary).to include("1 hamac")
  end
end
