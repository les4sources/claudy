require "rails_helper"

# Annulation d'un séjour depuis sa fiche (Michael 2026-09-05). « Annulé » est un
# STATUT (badge rouge, séjour toujours listé), pas une suppression. Il doit :
# sortir le séjour de l'agenda et libérer ses dates (propagation aux
# réservables), rester silencieux (aucun email, quel que soit le réservable),
# éteindre les activités encore actives, et se réactiver en attente.
RSpec.describe "Stays — annulation d'un séjour", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "admin-cancel@les4sources.be", password: "password123") }
  before { sign_in user }

  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end
  let(:space) { Space.create!(name: "Grande Salle", code: "GS", capacity: 40) }

  let(:arrival)   { Date.today + 60 }
  let(:departure) { Date.today + 62 }

  def create_stay(status:)
    draft = Reservations::Draft.new(
      lodging_id: hulotte.id, arrival_date: arrival, departure_date: departure,
      adults: 2, dogs_count: 0, first_name: "Alice", last_name: "Martin",
      email: "alice@example.com", phone: "0470111222"
    )
    Reservations::Builder.new(draft: draft, admin: true, source: "manual", status: status).tap(&:run!).stay
  end

  def booking_of(stay)
    stay.stay_items.where(bookable_type: "Booking").first.bookable
  end

  def cancel!(stay, headers: {})
    patch update_status_stay_path(stay), params: { status: "canceled" }, headers: headers
  end

  it "annule le séjour, propage au Booking, libère les dates et sort de l'agenda" do
    stay = create_stay(status: "confirmed")
    booking = booking_of(stay)
    expect(hulotte.available_between?(arrival, departure)).to be(false)

    get "/", params: { date: arrival.iso8601 }
    expect(response.body).to include(%(data-stay-id="#{stay.id}"))

    ActionMailer::Base.deliveries.clear
    cancel!(stay, headers: { "Accept" => "text/vnd.turbo-stream.html" })

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(stay.reload.status).to eq("canceled")
    expect(stay).to be_canceled
    expect(booking.reload.status).to eq("canceled")
    # Les dates sont rendues : le veto ne compte que les Booking confirmés.
    expect(hulotte.available_between?(arrival, departure)).to be(true)
    # Aucun email — ni Booking, ni séjour.
    expect(ActionMailer::Base.deliveries).to be_empty

    # La modale rafraîchie : badge rouge, réactivation proposée, plus d'annulation.
    expect(response.body).to include("Annulé")
    expect(response.body).to include("Réactiver le séjour")
    expect(response.body).not_to include("Annuler le séjour")
    expect(response.body).not_to include("Confirmer le séjour")

    # Le bloc a disparu de l'agenda.
    get "/", params: { date: arrival.iso8601 }
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(%(data-stay-id="#{stay.id}"))
  end

  it "reste silencieux même avec un espace rattaché (SpaceBooking sans email client)" do
    stay = create_stay(status: "confirmed")
    space_booking = SpaceBooking.create!(firstname: "Alice", lastname: "Martin", email: "alice@example.com",
                                         group_name: "Martin", from_date: arrival, to_date: arrival,
                                         status: "confirmed")
    SpaceReservation.create!(space: space, space_booking: space_booking, date: arrival)
    StayItem.create!(stay: stay, bookable: space_booking)
    ActionMailer::Base.deliveries.clear

    cancel!(stay)

    expect(space_booking.reload.status).to eq("canceled")
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "éteint les activités encore actives du séjour (comme à la suppression)" do
    stay = create_stay(status: "confirmed")
    experience = Experience.create!(name: "Poterie", price_cents: 2_000)
    slot = ExperienceAvailability.create!(experience: experience, available_on: arrival + 1, starts_at: "14:00")
    pending   = ExperienceBooking.create!(experience_availability: slot, stay: stay, participants: 2, status: "pending")
    confirmed = ExperienceBooking.create!(experience_availability: slot, stay: stay, participants: 1, status: "confirmed")

    cancel!(stay)

    expect(pending.reload.status).to eq("cancelled")
    expect(confirmed.reload.status).to eq("cancelled")
    expect(stay.reload.experience_bookings.active).to be_empty
  end

  it "réactive un séjour annulé en attente, sans email" do
    stay = create_stay(status: "confirmed")
    cancel!(stay)
    ActionMailer::Base.deliveries.clear

    patch update_status_stay_path(stay), params: { status: "pending" }

    expect(stay.reload.status).to eq("pending")
    expect(booking_of(stay).reload.status).to eq("pending")
    expect(ActionMailer::Base.deliveries).to be_empty
    # En attente : les dates restent libres, et la confirmation redevient possible.
    expect(hulotte.available_between?(arrival, departure)).to be(true)
    get stay_path(stay)
    expect(response.body).to include("Confirmer le séjour")
    expect(response.body).to include("Annuler le séjour")
  end

  it "arme « Annuler le séjour » en deux clics sur un séjour vivant" do
    stay = create_stay(status: "pending")

    get stay_path(stay)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Annuler le séjour")
    expect(response.body).to include('data-confirm-click-label-value="Vraiment annuler ?"')
    expect(response.body).not_to include("Réactiver le séjour")
  end

  it "n'expose pas le toggle en attente/confirmé sur un séjour annulé et conserve le statut à l'enregistrement" do
    stay = create_stay(status: "confirmed")
    cancel!(stay)

    get edit_stay_path(stay)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-stay-status-canceled="true"')
    expect(response.body).not_to include('id="stay_status_toggle"')

    # Le formulaire renvoie le statut courant : corriger une note ne ressuscite
    # pas un séjour annulé.
    patch stay_path(stay), params: {
      stay: {
        customer_mode: "existing", customer_id: stay.customer_id, new_customer: {},
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        adults: 2, children: 0, dogs_count: 0,
        lodging_id: hulotte.id, status: "canceled", notes: "Note corrigée après annulation"
      }
    }
    expect(response).to redirect_to(recent_stays_path)
    expect(stay.reload.status).to eq("canceled")
    expect(stay.notes).to include("Note corrigée après annulation")
    expect(booking_of(stay).reload.status).to eq("canceled")
    expect(hulotte.available_between?(arrival, departure)).to be(true)
  end
end
