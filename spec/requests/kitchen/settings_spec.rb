require "rails_helper"

# Paramètres > Cuisine (epic #219, phase 2).
RSpec.describe "Paramètres > Cuisine", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-kitchen-settings@les4sources.be", password: "password123") }
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
  before { sign_in user }

  it "affiche un bloc par famille avec les humains assignables" do
    get kitchen_settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Repas", "Buffets", "Apéros")
    expect(response.body).to include("Stéphanie")
    expect(response.body).to include("malau@les4sources.be")
  end

  it "enregistre l'offre, les responsables, les plafonds et les délais" do
    patch kitchen_settings_path, params: {
      kitchen: {
        repas:  { enabled: "1", default_human_id: steph.id, max_people: "30", lead_days: "10" },
        buffet: { enabled: "1", default_human_id: "", max_people: "", lead_days: "4" },
        apero:  { enabled: "0", default_human_id: "", max_people: "", lead_days: "" },
        coordinator_email: "accueil@les4sources.be"
      }
    }

    expect(response).to redirect_to(kitchen_settings_path)
    expect(Kitchen::Config.default_human("repas")).to eq(steph)
    expect(Kitchen::Config.max_people("repas")).to eq(30)
    expect(Kitchen::Config.lead_days("repas")).to eq(10)
    expect(Kitchen::Config.max_people("buffet")).to be_nil
    expect(Kitchen::Config.enabled?("apero")).to be(false)
    expect(Kitchen::Config.enabled?("buffet")).to be(true)
    expect(Kitchen::Config.coordinator_email).to eq("accueil@les4sources.be")
  end

  it "relit les valeurs enregistrées à la réouverture" do
    patch kitchen_settings_path, params: {
      kitchen: { repas: { enabled: "1", default_human_id: steph.id, max_people: "30", lead_days: "10" },
                 buffet: { enabled: "0" }, apero: { enabled: "1" }, coordinator_email: "accueil@les4sources.be" }
    }
    get kitchen_settings_path

    expect(response.body).to include("accueil@les4sources.be")
    expect(response.body).to include('value="30"')
  end
end
