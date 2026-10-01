require "rails_helper"

# Rattraper un séjour PASSÉ (Michael 2026-10-01) : l'équipe pose après coup le
# créneau d'une activité tenue, puis l'enregistre sur le séjour. La section
# « Activités » du formulaire doit proposer ce créneau passé, et un séjour d'une
# journée (arrivée = départ, zéro nuit) a bien des dates.
RSpec.describe "Formulaire séjour — activités d'un séjour passé", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:customer) { Customer.create!(email: "groupe-passe@example.org", first_name: "Groupe", last_name: "Passé") }
  let(:experience) { Experience.create!(name: "Bijoux en récup", duration_hours: 3) }
  let(:day) { Date.today - 10 }
  let!(:slot) { experience.experience_availabilities.create!(available_on: day, starts_at: "14:00") }
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: day, departure_date: day)
  end

  context "équipe" do
    let(:user) { User.create!(email: "equipe-passe@les4sources.be", password: "password123") }
    before { sign_in user }

    it "propose le créneau passé d'un séjour d'une journée" do
      get edit_stay_path(stay)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Bijoux en récup")
      expect(response.body).not_to include("Choisissez d'abord les dates du séjour pour voir les créneaux")
    end

    it "dit qu'il n'y a pas de créneau, pas qu'il manque les dates, quand la journée est vide" do
      slot.destroy

      get edit_stay_path(stay)

      expect(response.body).to include("Aucun créneau d'activité proposé sur ces dates.")
    end
  end

  describe "ExperienceAvailability.assignable_between" do
    let(:team) { User.create!(email: "equipe-fenetre@les4sources.be", password: "password123") }

    it "garde les créneaux passés dans la fenêtre du séjour pour l'équipe" do
      expect(ExperienceAvailability.assignable_between(team, day, day)).to include(slot)
    end

    it "reste sur l'à-venir sans fenêtre" do
      expect(ExperienceAvailability.assignable_between(team, nil, nil)).not_to include(slot)
    end

    it "reste sur l'à-venir pour un porteur restreint" do
      carrier = Human.create!(name: "Porteur")
      experience.update!(human: carrier)
      restricted = User.create!(email: "porteur-fenetre@les4sources.be", password: "password123",
                                human: carrier, restricted_to_experiences: true)

      expect(ExperienceAvailability.assignable_between(restricted, day, day)).not_to include(slot)
    end
  end
end
