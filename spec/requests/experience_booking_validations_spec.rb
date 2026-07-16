require "rails_helper"

# Epic #55 — Phase 2 : canal JETON (lien email) de validation d'activité.
RSpec.describe "ExperienceBookingValidations — canal jeton", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:customer) { Customer.create!(email: "client@example.com", customer_type: "individual") }
  let(:stay)     { Stay.create!(customer: customer, arrival_date: Date.today + 20, departure_date: Date.today + 22) }

  let(:porteur_a) { Human.create!(name: "Porteuse A", email: "a@example.com") }
  let(:user_a)    { User.create!(email: "a@example.com", password: "password123", human: porteur_a) }
  let(:exp_a)     { Experience.create!(name: "Balade ânes", human: porteur_a) }
  let(:avail_a)   { ExperienceAvailability.create!(experience: exp_a, available_on: Date.today + 21, starts_at: "10:00") }
  let(:booking)   { ExperienceBooking.create!(experience_availability: avail_a, stay: stay, participants: 2) }

  describe "GET show (page de confirmation)" do
    it "affiche un bouton de confirmation SANS muter la réservation" do
      get activity_validation_path(booking.validation_token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Confirmer cette activité")
      expect(booking.reload).to be_pending # aucune mutation sur GET
    end

    it "renvoie 404 pour un jeton invalide" do
      get activity_validation_path("jeton-bidon")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST confirm (validation 1 clic)" do
    it "valide LA bonne réservation et notifie le client" do
      token = booking.validation_token
      expect {
        post activity_validation_confirm_path(token)
      }.to have_enqueued_mail(ActivitySelectionMailer, :booking_confirmed)
      expect(booking.reload).to be_confirmed
    end

    it "ne re-valide pas une réservation déjà traitée (idempotent)" do
      booking.confirm!
      token = booking.validation_token
      expect {
        post activity_validation_confirm_path(token)
      }.not_to have_enqueued_mail(ActivitySelectionMailer, :booking_confirmed)
    end
  end

  describe "GET refuse (amorce du refus)" do
    it "exige une connexion (redirige vers le login) quand anonyme" do
      get activity_validation_refuse_path(booking.validation_token)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "connecté et propriétaire : renvoie vers le formulaire de refus admin" do
      sign_in user_a
      get activity_validation_refuse_path(booking.validation_token)
      expect(response).to redirect_to(new_refusal_experience_booking_path(booking))
    end

    it "connecté mais NON propriétaire : accès refusé" do
      autre = Human.create!(name: "Autre", email: "autre@example.com")
      autre_user = User.create!(email: "autre@example.com", password: "password123", human: autre)
      sign_in autre_user
      get activity_validation_refuse_path(booking.validation_token)
      expect(response).to have_http_status(:forbidden)
      expect(booking.reload).to be_pending
    end
  end
end
