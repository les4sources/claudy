require "rails_helper"

# Issue #133 — validation par l'équipe : approbation / refus d'une demande.
RSpec.describe "Demande de modification de séjour (admin)", type: :request do
  include ActiveJob::TestHelper

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  let(:customer) { Customer.create!(first_name: "Ana", last_name: "Lopez", email: "ana@example.com") }
  let!(:lodging) { Lodging.find_or_create_by!(name: "La Hulotte") { |l| l.price_night_cents = 48_500 } }

  let(:arrival)   { Date.current + 10 }
  let(:departure) { Date.current + 12 }

  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: arrival, departure_date: departure,
                 total_amount_cents: 74_500)
  end

  # Draft proposé : 3 nuits au lieu de 2 (agrandissement).
  def proposed_snapshot(nights: 3, from: arrival)
    Reservations::Draft.new(
      lodging_id: lodging.id,
      arrival_date: from,
      departure_date: from + nights,
      lodging_night_ids: [lodging.id.to_s] * nights,
      first_name: "Ana", last_name: "Lopez", email: "ana@example.com"
    ).to_h
  end

  def change_request(attrs = {})
    snapshot = attrs.delete(:snapshot) || proposed_snapshot
    total = Reservations::Draft.new(snapshot).quote.total_excluding_experiences_cents
    StayChangeRequest.create!({
      stay: stay,
      draft_snapshot: snapshot,
      new_total_cents: total,
      delta_cents: total - stay.total_amount_cents.to_i
    }.merge(attrs))
  end

  before do
    sign_in user
    ActionMailer::Base.deliveries.clear
  end

  describe "bloc sur la fiche séjour" do
    it "affiche la demande en attente, le delta et les deux actions" do
      change_request

      get stay_path(stay)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Demande de modification en attente")
      expect(response.body).to include("Total proposé")
      expect(response.body).to include("Approuver")
      expect(response.body).to include("Motif du refus")
    end

    it "n'affiche rien quand il n'y a pas de demande en attente" do
      get stay_path(stay)
      expect(response.body).not_to include("Demande de modification en attente")
    end
  end

  describe "POST approve_change_request" do
    it "applique la composition et recalcule le solde" do
      change = change_request

      perform_enqueued_jobs do
        post approve_change_request_stay_path(stay, change_request_id: change.id)
      end

      expect(response).to redirect_to(stay_path(stay))
      expect(change.reload).to be_approved
      expect(stay.reload.departure_date).to eq(arrival + 3)
      expect(stay.total_amount_cents).to eq(change.new_total_cents)
      # Le client est prévenu.
      expect(ActionMailer::Base.deliveries.map(&:to).flatten).to include("ana@example.com")
    end

    it "recopie l'IBAN et la consigne des 10 jours dans la note interne" do
      Payment.create!(stay: stay, amount_cents: 200_000, payment_method: "card", status: "paid")
      change = change_request(refund_iban: "BE68539007547034")

      post approve_change_request_stay_path(stay, change_request_id: change.id)

      expect(stay.reload.notes.to_s).to include("BE68539007547034")
      expect(stay.notes.to_s).to include(StayChangeRequest::REFUND_NOTICE)
    end

    it "re-vérifie la disponibilité à la validation et refuse si elle a sauté" do
      change = change_request
      (arrival..(arrival + 3)).each { |date| lodging.unavailabilities.create!(date: date) }

      post approve_change_request_stay_path(stay, change_request_id: change.id)

      follow_redirect!
      expect(response.body).to include("ne sont plus disponibles")
      expect(change.reload).to be_pending
      expect(stay.reload.departure_date).to eq(departure)
    end

    it "laisse forcer la disponibilité" do
      change = change_request
      (arrival..(arrival + 3)).each { |date| lodging.unavailabilities.create!(date: date) }

      post approve_change_request_stay_path(stay, change_request_id: change.id,
                                                  force_availability: "1")

      expect(change.reload).to be_approved
    end
  end

  describe "POST refuse_change_request" do
    it "refuse avec un motif et prévient le client" do
      change = change_request

      perform_enqueued_jobs do
        post refuse_change_request_stay_path(stay, change_request_id: change.id),
             params: { refusal_reason: "Le gîte est déjà réservé cette nuit-là." }
      end

      expect(change.reload).to be_refused
      expect(change.refusal_reason).to include("déjà réservé")
      # Le séjour n'a PAS bougé.
      expect(stay.reload.departure_date).to eq(departure)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq(["ana@example.com"])
      expect(mail.text_part.decoded).to include("déjà réservé")
    end

    it "exige un motif" do
      change = change_request

      post refuse_change_request_stay_path(stay, change_request_id: change.id),
           params: { refusal_reason: "  " }

      expect(change.reload).to be_pending
      follow_redirect!
      expect(response.body).to include("motif de refus est obligatoire")
    end
  end

  describe "sans authentification" do
    it "redirige vers la connexion" do
      change = change_request
      sign_out user

      post approve_change_request_stay_path(stay, change_request_id: change.id)

      expect(response).to redirect_to(new_user_session_path)
      expect(change.reload).to be_pending
    end
  end
end
