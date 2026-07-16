require "rails_helper"

# Epic #55 — Phase 2 : canal ADMIN de validation/refus des activités, avec
# scoping d'autorisation par porteur.
RSpec.describe "ExperienceBookings — canal admin", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:customer) { Customer.create!(email: "client@example.com", customer_type: "individual") }
  let(:stay)     { Stay.create!(customer: customer, arrival_date: Date.today + 20, departure_date: Date.today + 22) }

  # Porteuse A + son compte
  let(:porteur_a)  { Human.create!(name: "Porteuse A", email: "a@example.com") }
  let(:user_a)     { User.create!(email: "a@example.com", password: "password123", human: porteur_a) }
  let(:exp_a)      { Experience.create!(name: "Balade ânes", human: porteur_a) }
  let(:avail_a)    { ExperienceAvailability.create!(experience: exp_a, available_on: Date.today + 21, starts_at: "10:00") }
  let(:booking_a)  { ExperienceBooking.create!(experience_availability: avail_a, stay: stay, participants: 2) }

  # Porteur B + son compte (pour prouver le cloisonnement)
  let(:porteur_b)  { Human.create!(name: "Porteur B", email: "b@example.com") }
  let(:user_b)     { User.create!(email: "b@example.com", password: "password123", human: porteur_b) }
  let(:exp_b)      { Experience.create!(name: "Poterie", human: porteur_b) }
  let(:avail_b)    { ExperienceAvailability.create!(experience: exp_b, available_on: Date.today + 21, starts_at: "14:00") }
  let(:booking_b)  { ExperienceBooking.create!(experience_availability: avail_b, stay: stay, participants: 1) }

  describe "GET /experience_bookings (index)" do
    it "un porteur ne voit que ses propres activités" do
      booking_a; booking_b
      sign_in user_a
      get experience_bookings_path
      expect(response.body).to include("Balade ânes")
      expect(response.body).not_to include("Poterie")
    end

    it "un admin global voit toutes les activités" do
      booking_a; booking_b
      admin = User.create!(email: "staff@les4sources.be", password: "password123")
      sign_in admin
      get experience_bookings_path
      expect(response.body).to include("Balade ânes")
      expect(response.body).to include("Poterie")
    end
  end

  describe "PATCH /experience_bookings/:id/confirm" do
    it "le porteur valide SA réservation et le client est notifié" do
      sign_in user_a
      expect {
        patch confirm_experience_booking_path(booking_a)
      }.to have_enqueued_mail(ActivitySelectionMailer, :booking_confirmed)
      expect(booking_a.reload).to be_confirmed
    end

    it "un porteur ne peut PAS valider l'activité d'un autre porteur" do
      target = booking_b
      sign_in user_a
      patch confirm_experience_booking_path(target)
      expect(target.reload).to be_pending # inchangé
    end
  end

  describe "refus (formulaire + application)" do
    it "GET new_refusal affiche le formulaire de raison" do
      sign_in user_a
      get new_refusal_experience_booking_path(booking_a)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Raison du refus")
    end

    it "PATCH refuse avec raison refuse et notifie le client" do
      sign_in user_a
      expect {
        patch refuse_experience_booking_path(booking_a), params: { experience_booking: { refusal_reason: "Complet" } }
      }.to have_enqueued_mail(ActivitySelectionMailer, :booking_refused)
      expect(booking_a.reload).to be_refused
      expect(booking_a.refusal_reason).to eq("Complet")
    end

    it "PATCH refuse SANS raison ré-affiche le formulaire et ne refuse pas" do
      sign_in user_a
      patch refuse_experience_booking_path(booking_a), params: { experience_booking: { refusal_reason: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(booking_a.reload).to be_pending
    end

    it "un porteur ne peut pas refuser l'activité d'un autre porteur" do
      target = booking_b
      sign_in user_a
      patch refuse_experience_booking_path(target), params: { experience_booking: { refusal_reason: "Non" } }
      expect(target.reload).to be_pending
    end
  end
end
