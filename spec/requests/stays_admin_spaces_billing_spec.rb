require "rails_helper"

# Ménage legacy (refonte séjour 2026-07-22) : les champs « Facturation espaces »
# (Mode de paiement, Caution, Événement, Acompte) sont RETIRÉS du formulaire
# séjour admin (décision Michael). Les colonnes DB du SpaceBooking subsistent,
# mais le formulaire ne les écrit plus. Les heures d'arrivée/départ ont déjà
# migré vers le séjour (voir stay_times_spec). Ce spec verrouille l'ABSENCE des
# 4 champs et la parité (aucun paiement/aucun email à la création d'un espace).
RSpec.describe "Stays — champs de facturation espaces retirés", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-space-billing@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:lodging)      { Lodging.create!(name: "La Hulotte", summary: "gîte") }
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }
  let(:arrival)       { Date.today + 30 }
  let(:departure)     { Date.today + 32 }

  def base_params(overrides = {})
    {
      stay: {
        customer_mode: "new",
        new_customer: { first_name: "Alice", last_name: "Martin", email: "alice@example.com", phone: "0470111222" },
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        arrival_time: "14:00", departure_time: "11:00",
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: lodging.id, status: "pending"
      }.merge(overrides)
    }
  end

  def hall_param(kind: "grande_salle", date: nil, period: "journee")
    { "0" => { kind: kind, date: (date || arrival).iso8601, period: period } }
  end

  def space_booking_of(stay)
    stay.stay_items.where(bookable_type: "SpaceBooking").first.bookable
  end

  LEGACY_FIELDS = [
    'name="stay[space_billing][advance_amount]"',
    'name="stay[space_billing][deposit_amount]"',
    'name="stay[space_billing][payment_method]"',
    'name="stay[space_billing][event_id]"'
  ].freeze

  describe "GET /stays/new — les champs de facturation legacy ont disparu" do
    it "ne rend plus mode de paiement / caution / événement / acompte" do
      get new_stay_path
      expect(response).to have_http_status(:ok)
      LEGACY_FIELDS.each { |name| expect(response.body).not_to include(name) }
      expect(response.body).not_to include("Facturation espaces")
    end
  end

  describe "GET /stays/:id/edit — idem à l'édition d'un séjour avec espace" do
    it "ne rend plus les champs de facturation legacy" do
      post stays_path, params: base_params(halls: hall_param)
      stay = Stay.order(:created_at).last
      get edit_stay_path(stay)
      expect(response).to have_http_status(:ok)
      LEGACY_FIELDS.each { |name| expect(response.body).not_to include(name) }
    end
  end

  describe "POST /stays — création d'un séjour avec espace (sans facturation)" do
    it "crée le SpaceBooking sans paiement ni email (parité inchangée)" do
      post stays_path, params: base_params(halls: hall_param)
      expect(response).to redirect_to(recent_stays_path)

      stay = Stay.order(:created_at).last
      expect(space_booking_of(stay)).to be_present
      expect(stay.payments).to be_empty
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "ignore un sous-hash space_billing forgé (aucune écriture sur le SpaceBooking)" do
      post stays_path, params: base_params(
        halls: hall_param,
        space_billing: { advance_amount: "50", deposit_amount: "200", payment_method: "bank_transfer" }
      )
      sb = space_booking_of(Stay.order(:created_at).last)
      expect(sb.advance_amount_cents).to be_nil
      expect(sb.deposit_amount_cents).to be_nil
      expect(sb.payment_method).to be_nil
    end
  end
end
