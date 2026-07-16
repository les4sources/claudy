require "rails_helper"

# Epic #55 — Phase 6 : CRUD admin d'une activité SUR un séjour.
#   - ajout (choix explicite du statut initial pending vs confirmed),
#   - édition du nombre de participants,
#   - retrait (bascule en `cancelled`),
#   - impact immédiat sur le total du séjour et sur l'exigible,
#   - respect du cloisonnement porteur (mêmes portées que Phase 2).
RSpec.describe "ExperienceBookings — CRUD admin sur un séjour", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:customer) { Customer.create!(email: "client@example.com", customer_type: "individual") }
  let(:stay)     { Stay.create!(customer: customer, arrival_date: Date.today + 20, departure_date: Date.today + 22) }

  # Porteuse A + son compte + une activité tarifée (40 € + 15 €/pers).
  let(:porteur_a) { Human.create!(name: "Porteuse A", email: "a@example.com") }
  let(:user_a)    { User.create!(email: "a@example.com", password: "password123", human: porteur_a) }
  let(:exp_a)     { Experience.create!(name: "Balade ânes", human: porteur_a, fixed_price_cents: 4000, price_cents: 1500) }
  let(:avail_a)   { ExperienceAvailability.create!(experience: exp_a, available_on: Date.today + 21, starts_at: "10:00") }

  # Porteur B + son compte + son créneau (pour prouver le cloisonnement).
  let(:porteur_b) { Human.create!(name: "Porteur B", email: "b@example.com") }
  let(:user_b)    { User.create!(email: "b@example.com", password: "password123", human: porteur_b) }
  let(:exp_b)     { Experience.create!(name: "Poterie", human: porteur_b, price_cents: 2000) }
  let(:avail_b)   { ExperienceAvailability.create!(experience: exp_b, available_on: Date.today + 21, starts_at: "14:00") }

  # Compte staff/accueil (sans `human`) = admin global.
  let(:admin) { User.create!(email: "staff@les4sources.be", password: "password123") }

  describe "GET /stays/:id (section activités de la modale)" do
    it "affiche le formulaire d'ajout et liste les activités actives" do
      ExperienceBooking.create!(experience_availability: avail_a, stay: stay, participants: 2, status: "confirmed")
      avail_a # s'assure qu'un créneau proposable existe
      sign_in admin
      get stay_path(stay)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ajouter une activité")
      expect(response.body).to include("Balade ânes")
      expect(response.body).to include("stay_#{stay.id}_activities") # turbo-frame d'ancrage
    end
  end

  describe "POST /stays/:stay_id/experience_bookings (ajout)" do
    it "ajoute une activité PENDING : elle compte dans le total mais n'est PAS exigible" do
      sign_in admin
      expect {
        post stay_experience_bookings_path(stay), params: {
          experience_booking: { experience_availability_id: avail_a.id, participants: 2, status: "pending" }
        }
      }.to change(ExperienceBooking, :count).by(1)

      booking = ExperienceBooking.last
      expect(booking).to be_pending
      expect(booking.participants).to eq(2)

      stay.reload
      # 4000 (forfait) + 1500 × 2 = 7000, comptée dans le TOTAL prévu…
      expect(stay.total_amount_cents).to eq(7000)
      # …mais retirée de l'EXIGIBLE tant qu'elle n'est pas validée (Phase 3).
      expect(stay.payable_amount_cents).to eq(0)
    end

    it "ajoute une activité CONFIRMED : elle devient immédiatement exigible" do
      sign_in admin
      post stay_experience_bookings_path(stay), params: {
        experience_booking: { experience_availability_id: avail_a.id, participants: 2, status: "confirmed" }
      }

      expect(ExperienceBooking.last).to be_confirmed
      stay.reload
      expect(stay.total_amount_cents).to eq(7000)
      # Validée par l'admin → court-circuite la validation porteur → exigible.
      expect(stay.payable_amount_cents).to eq(7000)
    end

    it "respecte le statut choisi par l'admin (pas de statut imposé d'office)" do
      sign_in admin
      post stay_experience_bookings_path(stay), params: {
        experience_booking: { experience_availability_id: avail_a.id, participants: 1, status: "confirmed" }
      }
      expect(ExperienceBooking.last).to be_confirmed
    end

    it "un porteur ne peut PAS ajouter sur le créneau d'un AUTRE porteur" do
      sign_in user_a
      expect {
        post stay_experience_bookings_path(stay), params: {
          experience_booking: { experience_availability_id: avail_b.id, participants: 1, status: "confirmed" }
        }
      }.not_to change(ExperienceBooking, :count)
    end

    it "un porteur PEUT ajouter sur SON propre créneau" do
      sign_in user_a
      expect {
        post stay_experience_bookings_path(stay), params: {
          experience_booking: { experience_availability_id: avail_a.id, participants: 3, status: "pending" }
        }
      }.to change(ExperienceBooking, :count).by(1)
    end
  end

  describe "PATCH /experience_bookings/:id (édition des participants)" do
    it "modifie le nombre de participants et recalcule le total" do
      booking = ExperienceBooking.create!(experience_availability: avail_a, stay: stay, participants: 2, status: "confirmed")
      stay.recompute_aggregates!
      expect(stay.reload.total_amount_cents).to eq(7000)

      sign_in admin
      patch experience_booking_path(booking), params: { experience_booking: { participants: 5 } }

      expect(booking.reload.participants).to eq(5)
      # 4000 + 1500 × 5 = 11500
      expect(stay.reload.total_amount_cents).to eq(11500)
    end

    it "un porteur ne peut pas éditer l'activité d'un autre porteur" do
      target = ExperienceBooking.create!(experience_availability: avail_b, stay: stay, participants: 1, status: "pending")
      sign_in user_a
      patch experience_booking_path(target), params: { experience_booking: { participants: 9 } }
      expect(target.reload.participants).to eq(1)
    end
  end

  describe "DELETE /experience_bookings/:id (retrait)" do
    it "retire l'activité (bascule en cancelled) et la sort du total" do
      booking = ExperienceBooking.create!(experience_availability: avail_a, stay: stay, participants: 2, status: "confirmed")
      stay.recompute_aggregates!
      expect(stay.reload.total_amount_cents).to eq(7000)

      sign_in admin
      delete experience_booking_path(booking)

      expect(booking.reload).to be_cancelled
      expect(stay.reload.total_amount_cents).to eq(0)
    end

    it "un porteur ne peut pas retirer l'activité d'un autre porteur" do
      target = ExperienceBooking.create!(experience_availability: avail_b, stay: stay, participants: 1, status: "confirmed")
      sign_in user_a
      delete experience_booking_path(target)
      expect(target.reload).not_to be_cancelled
    end
  end
end
