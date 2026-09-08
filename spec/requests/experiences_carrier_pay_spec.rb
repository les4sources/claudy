require "rails_helper"

# Epic #244, phase 1 — le pôle et le tarif porteur dans l'écran d'activité.
RSpec.describe "Activités — pôle et tarif porteur", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-activites@les4sources.be", password: "password123") }
  let!(:carrier) { Human.create!(name: "Sébastien", email: "seb@les4sources.be") }
  let!(:team) { Team.create!(name: "Transmission") }

  before { sign_in user }

  def create_experience(**attrs)
    Experience.create!({ name: "Initiation vannerie", human: carrier, duration_hours: 2,
                         fixed_price_cents: 0, price_cents: 2_500, min_participants: 1 }.merge(attrs))
  end

  describe "le formulaire" do
    it "propose un pôle et un tarif horaire, avec le tarif général en indication" do
      get new_experience_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Transmission")
      expect(response.body).to include("Tarif horaire du porteur")
      expect(response.body).to include("40,00 €/h")
    end

    it "enregistre le pôle et le tarif saisi en euros" do
      post experiences_path, params: {
        experience: { name: "Vannerie", human_id: carrier.id, duration_hours: 2,
                      fixed_price: 0, price: 25, min_participants: 1,
                      team_id: team.id, carrier_hourly_rate: "55,50" }
      }

      experience = Experience.find_by(name: "Vannerie")
      expect(experience.team).to eq(team)
      expect(experience.carrier_hourly_rate_cents).to eq(5_550)
    end

    it "efface la surcharge quand on vide le champ" do
      experience = create_experience(carrier_hourly_rate_cents: 6_000)

      patch experience_path(experience), params: {
        experience: { name: experience.name, human_id: carrier.id, duration_hours: 2,
                      fixed_price: 0, price: 25, min_participants: 1, carrier_hourly_rate: "" }
      }

      expect(experience.reload.carrier_hourly_rate_cents).to be_nil
    end
  end

  describe "la fiche" do
    it "montre le pôle et le tarif effectif, avec le montant par prestation" do
      experience = create_experience(team: team)

      get experience_path(experience)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Transmission")
      expect(response.body).to include("40,00 €/h")
      expect(response.body).to include("tarif général")
      expect(response.body).to include("80,00 € par prestation")
    end

    it "annonce un tarif propre à l'activité quand il y en a un" do
      experience = create_experience(carrier_hourly_rate_cents: 6_000)

      get experience_path(experience)

      expect(response.body).to include("60,00 €/h")
      expect(response.body).to include("tarif propre à cette activité")
    end

    it "prévient qu'aucune rémunération n'est calculable sans durée" do
      experience = create_experience(duration_hours: nil)

      get experience_path(experience)

      expect(response.body).to include("aucune rémunération n'est calculable")
      expect(response.body).to include("Compléter la durée")
    end

    it "dit quand aucun pôle ne portera la charge" do
      experience = create_experience

      get experience_path(experience)

      expect(response.body).to include("Aucun pôle")
    end
  end

  describe "Paramètres > Tarifs" do
    it "expose le tarif horaire des porteurs dans un groupe « Activités »" do
      Rates::SeedFromCatalog.new.run

      get rates_path

      expect(response.body).to include("Activités")
      expect(response.body).to include("activity.carrier_hourly")
      expect(Rate.find_by(key: "activity.carrier_hourly").amount_cents).to eq(4_000)
    end
  end
end
