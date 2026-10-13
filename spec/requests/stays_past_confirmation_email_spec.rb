require "rails_helper"

# Confirmer un séjour DÉJÀ PASSÉ (Michael, 2026-10-13) : c'est une
# régularisation. Le bouton ouvre une modale qui demande s'il faut écrire au
# client ; le choix voyage dans `notify_customer`. Un séjour à venir garde son
# bouton habituel (et son email automatique).
RSpec.describe "Stays — confirmer un séjour passé", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-past-confirm@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  def create_pending_stay(arrival:, departure:)
    draft = Reservations::Draft.new(
      lodging_id: hulotte.id, arrival_date: arrival, departure_date: departure,
      adults: 2, dogs_count: 0, first_name: "Alice", last_name: "Martin",
      email: "alice@example.com", phone: "0470111222"
    )
    Reservations::Builder.new(draft: draft, admin: true, source: "manual", status: "pending").tap(&:run!).stay
  end

  let(:past_stay) { create_pending_stay(arrival: Date.current - 10, departure: Date.current - 8) }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

  before { ActionMailer::Base.deliveries.clear }

  it "affiche la modale de choix sur un séjour passé, pas sur un séjour à venir" do
    get stay_path(past_stay)
    expect(response.body).to include("Ce séjour est déjà passé", "Confirmer sans email", "Confirmer et envoyer l&#39;email", "notify_customer=1")

    future = create_pending_stay(arrival: Date.current + 30, departure: Date.current + 32)
    get stay_path(future)
    expect(response.body).to include("Confirmer le séjour")
    expect(response.body).not_to include("Ce séjour est déjà passé")
  end

  it "confirme sans email quand on le choisit" do
    patch update_status_stay_path(past_stay), params: { status: "confirmed", notify_customer: "0" }, headers: turbo

    expect(past_stay.reload.status).to eq("confirmed")
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(past_stay.confirmation_email_sent_at).to be_nil
  end

  it "confirme et envoie l'email quand on le choisit, malgré la date passée" do
    patch update_status_stay_path(past_stay), params: { status: "confirmed", notify_customer: "1" }, headers: turbo

    expect(past_stay.reload.status).to eq("confirmed")
    expect(ActionMailer::Base.deliveries.map { |m| m[:tag]&.value }).to eq(["stay_confirmed"])
    expect(ActionMailer::Base.deliveries.first.to).to eq(["alice@example.com"])
    expect(past_stay.confirmation_email_sent_at).to be_present
  end

  it "garde l'email automatique d'un séjour à venir quand rien n'est précisé" do
    future = create_pending_stay(arrival: Date.current + 30, departure: Date.current + 32)
    patch update_status_stay_path(future), params: { status: "confirmed" }, headers: turbo

    expect(ActionMailer::Base.deliveries.map { |m| m[:tag]&.value }).to eq(["stay_confirmed"])
  end
end
