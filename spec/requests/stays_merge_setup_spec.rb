require "rails_helper"

# Étape A de la fusion (POST /stays/merge_setup) — la carte de désignation du
# séjour survivant est enrichie pour aider l'admin à choisir : email du client,
# badge statut, canal d'attribution, date de saisie et chips de présence de notes.
RSpec.describe "Fusion — carte de désignation enrichie (merge_setup)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)    { User.create!(email: "agent@les4sources.be", password: "password123") }
  let(:lodging) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }

  before { sign_in user }

  # Un séjour = un hébergement rattaché (StayItem), avec un client identifiable.
  def stay_with_booking(email:, status:, source:, from:, to:,
                        booking_notes: nil, public_notes: nil, stay_notes: nil)
    customer = Customer.create!(email: email, first_name: "Client", customer_type: "individual")
    booking = Booking.create!(firstname: "Client", group_name: "Groupe", lodging: lodging,
                              from_date: from, to_date: to, adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging", price_cents: 0,
                              notes: booking_notes, public_notes: public_notes)
    stay = Stay.create!(customer: customer, source: source, status: status,
                        arrival_date: from, departure_date: to, notes: stay_notes)
    StayItem.create!(stay: stay, bookable: booking)
    stay
  end

  it "rend email, badge statut, canal, date de saisie et la chip note interne" do
    from = Date.today.next_occurring(:friday)
    stay_a = stay_with_booking(email: "alice@example.com", status: "confirmed",
                               source: "reservation", from: from, to: from + 1,
                               booking_notes: "Note interne booking")
    stay_b = stay_with_booking(email: "bob@example.com", status: "pending",
                               source: "manual", from: from, to: from + 2)

    post "/stays/merge_setup", params: { stay_ids: [stay_a.id, stay_b.id] }

    expect(response).to have_http_status(:ok)
    # Email du client sur chaque carte.
    expect(response.body).to include("alice@example.com")
    expect(response.body).to include("bob@example.com")
    # Badge statut (décorateur StayDecorator#status_badge).
    expect(response.body).to include("Confirmé")
    expect(response.body).to include("En attente")
    # Canal / source.
    expect(response.body).to include("Funnel")
    expect(response.body).to include("Manuel")
    # Date de saisie (repère original vs doublon).
    expect(response.body).to include("saisi le")
    # Chip note interne : stay_a porte une note sur son booking.
    expect(response.body).to include("note interne")
  end

  it "affiche la chip « note publique » quand un bookable porte une note publique ActionText" do
    from = Date.today.next_occurring(:friday)
    stay_a = stay_with_booking(email: "carol@example.com", status: "confirmed",
                               source: "manual", from: from, to: from + 1,
                               public_notes: "Bienvenue chez nous !")
    stay_b = stay_with_booking(email: "dave@example.com", status: "confirmed",
                               source: "manual", from: from, to: from + 1)

    post "/stays/merge_setup", params: { stay_ids: [stay_a.id, stay_b.id] }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("note publique")
  end
end
