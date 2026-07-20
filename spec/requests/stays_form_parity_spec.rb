require "rails_helper"

# Parité funnel du form de composition Séjour admin (issue « form parity ») :
#   - Volet 4 : le statut est un SWITCH accessible (En attente ↔ Confirmé),
#     avec hidden `pending` de repli → coché = confirmed, décoché = pending.
#   - Volet 3 : canal (source) et plateforme sont des RADIOS (plus des selects).
RSpec.describe "Stays — form parité (switch statut + radios attribution)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-parity@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:lodging) { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let!(:room)    { lodging.rooms.create!(name: "Chambre Hulotte", level: 1) }
  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }

  def base_params(overrides = {})
    {
      stay: {
        customer_mode: "new",
        new_customer: { first_name: "Alice", last_name: "Martin", email: "alice@example.com", phone: "0470111222" },
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        adults: 2, children: 0, dogs_count: 0, lodging_id: lodging.id
      }.merge(overrides)
    }
  end

  describe "Volet 4 — switch de statut" do
    it "rend un switch accessible avec repli hidden pending" do
      get new_stay_path
      expect(response.body).to include('role="switch"')
      expect(response.body).to include('id="stay_status_toggle"')
      # Hidden de repli : name en double, Rack retient la dernière valeur.
      expect(response.body).to match(%r{<input type="hidden" name="stay\[status\]" value="pending"})
      # Le checkbox porte la valeur confirmed (attributs triés par Slim).
      expect(response.body).to match(%r{<input[^>]*id="stay_status_toggle"[^>]*value="confirmed"})
    end

    it "coché → séjour confirmed" do
      post stays_path, params: base_params(status: "confirmed")
      expect(Stay.order(:created_at).last.status).to eq("confirmed")
    end

    it "décoché (seul le hidden est soumis) → séjour pending" do
      post stays_path, params: base_params(status: "pending")
      expect(Stay.order(:created_at).last.status).to eq("pending")
    end

    it "présélectionne l'état confirmé à l'édition" do
      post stays_path, params: base_params(status: "confirmed")
      stay = Stay.order(:created_at).last
      get edit_stay_path(stay)
      # Attributs triés par Slim : `checked` précède `id`.
      expect(response.body).to match(%r{<input[^>]*checked[^>]*id="stay_status_toggle"})
    end
  end

  describe "Volet 3 — radios attribution (source + plateforme)" do
    it "rend le canal et la plateforme en radios (plus des selects)" do
      get new_stay_path
      # Slim trie les attributs → name/type/value se retrouvent consécutifs.
      expect(response.body).to include('name="stay[source]" type="radio" value="manual"')
      expect(response.body).to include('name="stay[source]" type="radio" value="ota"')
      expect(response.body).to include('name="stay[platform]" type="radio" value="web"')
      expect(response.body).to include('name="stay[platform]" type="radio" value="airbnb"')
      expect(response.body).to include('name="stay[platform]" type="radio" value="bookingdotcom"')
      # Plus aucun <select> de canal/plateforme.
      expect(response.body).not_to include('select name="stay[source]"')
      expect(response.body).not_to include('select name="stay[platform]"')
    end

    it "persiste source + plateforme choisies via les radios" do
      post stays_path, params: base_params(source: "ota", platform: "airbnb",
                                           status: "confirmed", price_override: "500")
      stay = Stay.order(:created_at).last
      expect(stay.source).to eq("ota")
      booking = stay.stay_items.where(bookable_type: "Booking").first.bookable
      expect(booking.platform).to eq("airbnb")
    end
  end
end
