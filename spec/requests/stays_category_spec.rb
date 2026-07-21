require "rails_helper"

# Catégorie de séjour côté admin (Michael 2026-07-21) : le form de création la
# porte via le Draft (comme `group_name`), la modale l'affiche, et un
# `PATCH /stays/:id/update_category` la change sans ouvrir le form d'édition.
RSpec.describe "Stays — catégorie (admin)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-cat@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:lodging)  { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  def base_params(overrides = {})
    {
      stay: {
        customer_mode: "new",
        new_customer: { first_name: "Alice", last_name: "Martin", email: "alice-cat@example.com", phone: "0470111222" },
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: lodging.id, status: "pending"
      }.merge(overrides)
    }
  end

  def create_stay(category: nil)
    draft = Reservations::Draft.new(
      lodging_id: lodging.id, arrival_date: arrival, departure_date: departure,
      adults: 2, first_name: "Alice", last_name: "Martin",
      email: "alice-cat@example.com", phone: "0470111222", category: category
    )
    Reservations::Builder.new(draft: draft, admin: true, status: "pending", source: "manual").tap(&:run!).stay
  end

  describe "POST /stays (create) avec catégorie" do
    it "persiste la catégorie choisie sur le Stay" do
      post stays_path, params: base_params(category: "wedding")
      expect(Stay.order(:created_at).last.category).to eq("wedding")
    end

    it "laisse la catégorie nil quand l'option vide est choisie" do
      post stays_path, params: base_params(category: "")
      expect(Stay.order(:created_at).last.category).to be_nil
    end
  end

  describe "le form NEW propose les 12 catégories (les4sources incluse côté admin)" do
    it "rend le select complet" do
      get new_stay_path
      expect(response.body).to include("stay[category]")
      expect(response.body).to include("Mariage")
      expect(response.body).to include("Les 4 Sources")
      expect(response.body).to include("Retraite/Stage")
    end
  end

  describe "la modale séjour affiche la catégorie" do
    it "montre le libellé FR et le formulaire de changement rapide" do
      stay = create_stay(category: "family")
      get stay_path(stay, modal: 1)
      expect(response.body).to include("Catégorie")
      expect(response.body).to include("Famille")
      expect(response.body).to include(update_category_stay_path(stay))
    end
  end

  describe "PATCH /stays/:id/update_category" do
    it "change la catégorie et redirige vers la fiche séjour" do
      stay = create_stay(category: "family")
      patch update_category_stay_path(stay), params: { stay: { category: "birthday" } }
      expect(response).to redirect_to(stay_path(stay))
      expect(stay.reload.category).to eq("birthday")
    end

    it "vide la catégorie quand l'option vide est postée" do
      stay = create_stay(category: "family")
      patch update_category_stay_path(stay), params: { stay: { category: "" } }
      expect(stay.reload.category).to be_nil
    end

    it "exige une session Devise" do
      stay = create_stay
      sign_out user
      patch update_category_stay_path(stay), params: { stay: { category: "wedding" } }
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
