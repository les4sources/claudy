require "rails_helper"

# Confirmation en deux clics sur les boutons de changement de statut d'un séjour
# (fiche + modale calendrier). Le comportement JS (morphing du bouton) est
# vérifié au navigateur ; ici on garantit seulement que les deux boutons
# portent bien les data-attributes du contrôleur Stimulus `confirm-click`.
RSpec.describe "Stays — confirmation deux clics sur le statut", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-confirmclick@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  let(:arrival)   { Date.today + 60 }
  let(:departure) { Date.today + 62 }

  def create_pending_stay
    draft = Reservations::Draft.new(
      lodging_id: hulotte.id, arrival_date: arrival, departure_date: departure,
      adults: 2, dogs_count: 0, first_name: "Alice", last_name: "Martin",
      email: "alice@example.com", phone: "0470111222"
    )
    Reservations::Builder.new(draft: draft, admin: true, source: "manual", status: "pending").tap(&:run!).stay
  end

  it "arme le bouton « Confirmer le séjour » avec le contrôleur confirm-click" do
    stay = create_pending_stay

    get stay_path(stay)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Confirmer le séjour")
    # Le contrôleur est accroché au form généré par button_to, sur son submit.
    expect(response.body).to include('data-controller="confirm-click"')
    expect(response.body).to include("submit-&gt;confirm-click#confirm")
    expect(response.body).to include('data-confirm-click-label-value="Êtes-vous sûr·e ?"')
    # La cible button permet au contrôleur de morpher le libellé.
    expect(response.body).to include('data-confirm-click-target="button"')
  end

  it "arme le bouton « Repasser en attente » avec le contrôleur confirm-click" do
    stay = create_pending_stay
    patch update_status_stay_path(stay), params: { status: "confirmed" }

    get stay_path(stay)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Repasser en attente")
    expect(response.body).to include('data-controller="confirm-click"')
    expect(response.body).to include("submit-&gt;confirm-click#confirm")
    expect(response.body).to include('data-confirm-click-label-value="Êtes-vous sûr·e ?"')
    expect(response.body).to include('data-confirm-click-target="button"')
  end
end
