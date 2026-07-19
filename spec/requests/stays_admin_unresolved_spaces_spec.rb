require "rails_helper"

# Issue #75 — fiabiliser le mapping clé↔`Space` et ne JAMAIS perdre en silence un
# espace devisé mais non persistable. Deux garanties :
#   1. un espace dont la clé ne matche aucune `Space` → warning remonté (flash),
#      pas de SpaceBooking fantôme ;
#   2. la résolution s'appuie sur le `Space.code` STABLE, insensible au renommage
#      de l'affichage.
RSpec.describe "Stays — espaces non résolus & mapping stable (issue #75)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-unresolved@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:lodging) { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  def base_params(overrides = {})
    {
      stay: {
        customer_mode: "new",
        new_customer: { first_name: "Alice", last_name: "Martin", email: "alice@example.com", phone: "0470111222" },
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: lodging.id, status: "pending"
      }.merge(overrides)
    }
  end

  def hall_param(kind:, period: "journee")
    { "0" => { kind: kind, date: arrival.iso8601, period: period } }
  end

  describe "espace non résolu (aucune Space correspondante)" do
    it "crée le séjour, ne persiste PAS de SpaceBooking et remonte un warning" do
      # Aucune Space "Cuisine professionnelle"/code CUI en base.
      expect(Space.find_by(code: "CUI")).to be_nil

      expect {
        post stays_path, params: base_params(halls: hall_param(kind: "cuisine_pro"))
      }.to change(Stay, :count).by(1)
       .and change(SpaceBooking, :count).by(0)

      expect(response).to redirect_to(recent_stays_path)
      expect(flash[:alert]).to match(/non enregistrable/i)
      expect(flash[:alert]).to include("Cuisine professionnelle")
    end
  end

  describe "espace résolu → persisté, pas de warning" do
    it "persiste le SpaceBooking et ne remonte aucun warning d'espace" do
      Space.create!(name: "Grande Salle", capacity: 1)

      expect {
        post stays_path, params: base_params(halls: hall_param(kind: "grande_salle"))
      }.to change(SpaceBooking, :count).by(1)

      expect(response).to redirect_to(recent_stays_path)
      expect(flash[:alert]).to be_blank
    end
  end

  describe "résolution par le code stable (renommage de l'affichage)" do
    it "résout grande_salle via Space.code même si le nom a changé" do
      # Nom d'affichage renommé, HORS de la liste de noms candidats, mais code stable.
      renamed = Space.create!(name: "Salle du Tilleul rénovée", code: "TIL", capacity: 1)

      post stays_path, params: base_params(lodging_id: "", halls: hall_param(kind: "grande_salle"))
      expect(response).to redirect_to(recent_stays_path)

      stay = Stay.order(:created_at).last
      sb = stay.stay_items.where(bookable_type: "SpaceBooking").first&.bookable
      expect(sb).to be_present
      expect(sb.space_reservations.map(&:space)).to eq([renamed])
      expect(flash[:alert]).to be_blank
    end
  end
end
