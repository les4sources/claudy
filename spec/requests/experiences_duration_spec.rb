require "rails_helper"

# Phase 3 de l'épic #25 — durée numérique en heures (champ `duration_hours`).
RSpec.describe "Experiences — durée en heures", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent@les4sources.be", password: "password123") }
  before { sign_in user }

  describe "GET /experiences/new" do
    it "affiche le champ « Durée en heures »" do
      get new_experience_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Durée en heures")
      expect(response.body).to include("experience[duration_hours]")
    end
  end

  describe "POST /experiences" do
    it "persiste la durée numérique en heures" do
      post experiences_path, params: {
        experience: {
          name: "Atelier pain au four",
          fixed_price: "0",
          price: "15",
          min_participants: "1",
          duration: "une demi-journée",
          duration_hours: "2.5"
        }
      }
      experience = Experience.find_by(name: "Atelier pain au four")
      expect(experience).to be_present
      expect(experience.duration_hours).to eq(2.5)
      expect(experience.duration).to eq("une demi-journée")
      expect(experience.block_duration_minutes).to eq(150)
    end
  end

  describe "PATCH /experiences/:id" do
    it "met à jour la durée numérique" do
      experience = Experience.create!(name: "Balade nature", fixed_price_cents: 0)
      patch experience_path(experience), params: {
        experience: { duration_hours: "3" }
      }
      expect(experience.reload.duration_hours).to eq(3)
    end
  end
end
