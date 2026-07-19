require "rails_helper"

# Epic #66, Phase 2 — Espaces dans la composition du Séjour admin. Le CRUD admin
# crée/édite un SpaceBooking + StayItem depuis les espaces choisis (form `halls`),
# permet un séjour « espaces seuls » (sans hébergement), et n'appelle jamais
# Stripe ni d'email client forcé.
RSpec.describe "Stays — espaces (epic #66, Phase 2)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-spaces@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:lodging)      { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }
  let(:arrival)       { Date.today + 30 }
  let(:departure)     { Date.today + 32 }
  let(:grande_salle_journee_cents) { 29_000 }
  let(:hulotte_two_nights_cents)   { 74_500 }

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

  def hall_param(kind: "grande_salle", date: nil, period: "journee")
    { "0" => { kind: kind, date: (date || arrival).iso8601, period: period } }
  end

  describe "POST /stays — hébergement + espace" do
    it "crée un SpaceBooking + StayItem et intègre l'espace au total" do
      expect {
        post stays_path, params: base_params(halls: hall_param)
      }.to change(Stay, :count).by(1)
       .and change(SpaceBooking, :count).by(1)
       .and change(Booking, :count).by(1)

      stay = Stay.order(:created_at).last
      sb = stay.stay_items.where(bookable_type: "SpaceBooking").first.bookable
      expect(sb.space_reservations.map(&:space)).to eq([grande_salle])
      expect(stay.total_amount_cents).to eq(hulotte_two_nights_cents + grande_salle_journee_cents)
      expect(stay.payments).to be_empty # aucun Stripe
    end
  end

  describe "POST /stays — séjour espaces seuls (sans hébergement)" do
    it "crée un séjour sans Booking, avec son SpaceBooking persisté" do
      expect {
        post stays_path, params: base_params(lodging_id: "", halls: hall_param)
      }.to change(Stay, :count).by(1)
       .and change(SpaceBooking, :count).by(1)
       .and change(Booking, :count).by(0)

      stay = Stay.order(:created_at).last
      expect(stay.stay_items.where(bookable_type: "Booking")).to be_empty
      expect(stay.stay_items.where(bookable_type: "SpaceBooking").count).to eq(1)
      expect(stay.total_amount_cents).to eq(grande_salle_journee_cents)
      expect(stay.arrival_date).to eq(arrival)
      expect(stay.departure_date).to eq(departure)
    end
  end

  describe "PATCH /stays/:id — édition d'un séjour espaces seuls" do
    def create_spaces_only_stay
      draft = Reservations::Draft.new(
        lodging_id: nil, arrival_date: arrival, departure_date: departure,
        first_name: "Alice", last_name: "Martin", email: "alice@example.com", phone: "0470111222",
        halls: [{ kind: "grande_salle", date: arrival.iso8601, period: "journee" }]
      )
      builder = Reservations::Builder.new(draft: draft, admin: true, source: "manual")
      builder.run!
      builder.stay
    end

    def update_params(stay, overrides = {})
      {
        stay: {
          customer_mode: "existing", customer_id: stay.customer_id, new_customer: {},
          arrival_date: arrival.iso8601, departure_date: departure.iso8601,
          adults: 2, children: 0, dogs_count: 0,
          lodging_id: "", status: "pending"
        }.merge(overrides)
      }
    end

    it "préremplit le form d'édition avec l'espace existant" do
      stay = create_spaces_only_stay
      get edit_stay_path(stay)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Espaces")
      # L'espace existant est présélectionné (grande_salle / journée) et chiffré.
      expect(response.body).to include('selected="selected" value="grande_salle"')
      expect(response.body).to include('selected="selected" value="journee"')
      expect(response.body).to include("Grande salle — ")
    end

    it "change la période de l'espace et recalcule le total" do
      stay = create_spaces_only_stay
      expect(stay.total_amount_cents).to eq(grande_salle_journee_cents)

      # journée → journée + soirée = 380 € (38 000 c) pour la grande salle.
      patch stay_path(stay), params: update_params(stay, halls: hall_param(period: "journee_et_soiree"))
      expect(response).to redirect_to(recent_stays_path)

      stay.reload
      sb = stay.stay_items.where(bookable_type: "SpaceBooking").first.bookable
      expect(sb.space_reservations.first.duration).to eq("journee_et_soiree")
      expect(stay.total_amount_cents).to eq(38_000)
    end

    it "retire l'espace en vidant les lignes → refusé (séjour deviendrait vide)" do
      stay = create_spaces_only_stay
      patch stay_path(stay), params: update_params(stay) # ni lodging ni halls
      expect(response).to have_http_status(:unprocessable_entity)
      # Issue #80 : la contrainte de composition s'élargit aux activités/repas.
      expect(response.body).to include("un emplacement camping/van, une activité ou un repas")
    end
  end

  describe "capacité / force-dispo (édition)" do
    it "force l'ajout d'un espace complet avec avertissement" do
      # Grande salle complète à l'arrivée (capacity 1, une résa confirmée).
      occ = SpaceBooking.create!(firstname: "Occ", from_date: arrival, to_date: arrival, status: "confirmed")
      occ.space_reservations.create!(space: grande_salle, date: arrival, duration: "journee")

      post stays_path, params: base_params(lodging_id: "", halls: hall_param, force_availability: "1")
      expect(response).to redirect_to(recent_stays_path)
      expect(flash[:alert]).to match(/forçant la disponibilité/i)
      expect(SpaceBooking.where(status: "pending").count).to eq(1)
    end
  end
end
