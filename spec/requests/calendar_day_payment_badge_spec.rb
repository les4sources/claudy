require "rails_helper"

# Badge de paiement des cartes « infos du jour » (Michael 2026-08-21). Les
# popovers lisaient la colonne `payment_status` du réservable, figée à la
# création : un séjour soldé s'affichait « Non payée ». La vérité vit sur le
# séjour, qui recalcule son statut à chaque paiement encaissé.
RSpec.describe "Cartes du jour — badge de paiement", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-paiement@les4sources.be", password: "password123") }
  let(:room) { Room.create!(name: "Chambre P", code: "CHP", level: 1) }

  before { sign_in user }

  # Le popover de la carte : on part du lien vers la réservation et on prend la
  # suite, où vit le badge. Le bandeau varie (check-in / séjour en cours), pas ce
  # lien.
  def carte_du_jour(booking)
    response.body[/#{Regexp.escape(booking_path(booking))}.{0,900}/m]
  end

  it "affiche le statut du SÉJOUR, pas la colonne figée de la réservation" do
    today = Date.today

    customer = Customers::UpsertByEmail.call(email: "solde@example.com",
                                             attrs: { first_name: "Soldé" })
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: today, departure_date: today + 1)

    # La réservation garde « pending » — c'est elle qui mentait sur la carte.
    booking = Booking.create!(firstname: "Soldé", lodging: nil,
                              from_date: today, to_date: today + 1,
                              adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging",
                              price_cents: 17_142, payment_status: "pending")
    Reservation.create!(booking: booking, room: room, date: today)
    StayItem.create!(stay: stay, bookable: booking)

    Payment.create!(stay: stay, amount_cents: 17_142, status: "paid",
                    payment_method: "online", paid_on: today)

    # On NE recalcule PAS `stay.payment_status` : tous les chemins d'encaissement
    # ne l'appellent pas. Le badge doit dire vrai malgré les deux colonnes
    # périmées, parce qu'il compte l'argent réellement encaissé.
    expect(stay.reload.payment_status).to eq("pending")
    expect(booking.reload.payment_status).to eq("pending")
    expect(stay.amount_paid_cents).to eq(17_142)

    get "/"

    expect(response).to have_http_status(:ok)
    carte = carte_du_jour(booking)
    expect(carte).to include("Payée")
    expect(carte).not_to include("Non payée")
  end

  it "n'affiche aucun badge sur un séjour à 0 € dont rien n'est dû" do
    today = Date.today

    customer = Customers::UpsertByEmail.call(email: "gratuit@example.com",
                                             attrs: { first_name: "Gratuit" })
    stay = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                        arrival_date: today, departure_date: today + 1)
    booking = Booking.create!(firstname: "Gratuit", lodging: nil,
                              from_date: today, to_date: today + 1,
                              adults: 2, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging",
                              price_cents: 0)
    Reservation.create!(booking: booking, room: room, date: today)
    StayItem.create!(stay: stay, bookable: booking)

    get "/"

    expect(response).to have_http_status(:ok)
    carte = carte_du_jour(booking)
    expect(carte).not_to include("Non payée")
    expect(carte).not_to include("Payée")
  end

  it "garde la colonne du réservable pour une occupation SANS séjour" do
    today = Date.today

    booking = Booking.create!(firstname: "Orphelin", lodging: nil,
                              from_date: today, to_date: today + 1,
                              adults: 1, children: 0, babies: 0,
                              status: "confirmed", booking_type: "lodging",
                              price_cents: 5_000, payment_status: "pending")
    Reservation.create!(booking: booking, room: room, date: today)

    get "/"

    expect(response).to have_http_status(:ok)
    expect(carte_du_jour(booking)).to include("Non payée")
  end
end
