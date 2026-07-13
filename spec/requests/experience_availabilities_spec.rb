require "rails_helper"

# Epic #25, Phase 4 — calendrier hebdo : poser/retirer un bloc en un clic.
RSpec.describe "Disponibilités d'activité (calendrier hebdo)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "porteur@les4sources.be", password: "password123") }
  let(:experience) { Experience.create!(name: "Balade en forêt", duration_hours: 2) }
  let(:monday) { Date.today.beginning_of_week(:monday) }

  before { sign_in user }

  describe "GET /experiences/:id" do
    it "rend le calendrier de la semaine en cours" do
      get experience_path(experience)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-week-calendar")
      expect(response.body).to include("Calendrier des disponibilités")
      # Blocs de 2h de 8h à 22h -> 7 créneaux, du lundi au dimanche.
      expect(response.body).to include("#{monday.iso8601} 08:00")
      expect(response.body).to include("#{(monday + 6).iso8601} 20:00")
    end

    it "navigue vers une autre semaine via ?week=" do
      other_week = (monday + 21).iso8601
      get experience_path(experience, week: other_week)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("#{other_week} 08:00")
    end

    it "invite à renseigner la durée quand l'activité n'en a pas" do
      no_duration = Experience.create!(name: "Atelier sans durée")
      get experience_path(no_duration)

      expect(response.body).to include("durée de l&#39;activité")
      expect(response.body).not_to include("data-availability-slot")
    end

    it "marque le créneau posé comme occupé" do
      experience.experience_availabilities.create!(available_on: monday + 2, starts_at: "10:00")

      get experience_path(experience)

      expect(response.body).to include('data-availability-state="taken"')
    end
  end

  describe "POST — poser un bloc" do
    it "crée la disponibilité avec la durée de l'activité et revient sur la semaine affichée" do
      week = (monday + 7).iso8601

      expect {
        post experience_experience_availabilities_path(experience, week: week),
             params: { experience_availability: { available_on: (monday + 8).iso8601, starts_at: "14:00" } }
      }.to change(ExperienceAvailability, :count).by(1)

      availability = ExperienceAvailability.last
      expect(availability.duration_minutes).to eq(120)
      expect(response).to redirect_to(experience_path(experience, week: week))
    end

    it "refuse un chevauchement et le signale" do
      experience.experience_availabilities.create!(available_on: monday + 1, starts_at: "10:00")

      expect {
        post experience_experience_availabilities_path(experience),
             params: { experience_availability: { available_on: (monday + 1).iso8601, starts_at: "11:00" } }
      }.not_to change(ExperienceAvailability, :count)

      expect(flash[:alert]).to match(/chevauche/)
    end
  end

  describe "DELETE — retirer un bloc" do
    it "supprime la disponibilité et revient sur la semaine affichée" do
      availability = experience.experience_availabilities.create!(available_on: monday + 3, starts_at: "16:00")
      week = monday.iso8601

      expect {
        delete experience_experience_availability_path(experience, availability, week: week)
      }.to change(ExperienceAvailability, :count).by(-1)

      expect(response).to redirect_to(experience_path(experience, week: week))
    end
  end
end
