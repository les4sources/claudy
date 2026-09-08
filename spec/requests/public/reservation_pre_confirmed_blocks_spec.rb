require "rails_helper"

# Décision Michael du 2026-09-08 : une demande PRÉ-CONFIRMÉE tient ses dates.
# Le funnel public est le premier endroit où cela doit se voir — c'est lui qui
# vend les nuits. Sans ce verrou, un visiteur pouvait composer un séjour sur des
# nuits déjà promises à quelqu'un d'autre par le Pôle Accueil.
RSpec.describe "Public::Reservations — une nuit pré-confirmée est indisponible", type: :request do
  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre H", level: 1)
    l
  end

  let(:arrivee) { Date.today + 100 }
  let(:depart)  { Date.today + 102 }

  def occupe(status)
    booking = Booking.create!(firstname: "Occ", from_date: arrivee, to_date: depart,
                              adults: 1, status: status)
    (arrivee...depart).each do |date|
      Reservation.create!(booking: booking, room: hulotte.rooms.first, date: date)
    end
    booking
  end

  def composer
    post "/reservation/sejour", params: {
      reservation: { arrival_date: arrivee.iso8601, departure_date: depart.iso8601, adults: 2 }
    }
    get "/reservation/composer"
  end

  # La grille sérialise `@lodging_availability` en JSON dans le DOM : c'est la
  # vérité que lit le Stimulus. On l'interroge plutôt que de deviner une classe
  # CSS, qui bougera au premier repassage design.
  def disponibilites_pour(lodging)
    json = response.body[/data-public--stay-calendar-avail-value="([^"]*)"/, 1]
    raise "grille de dispo introuvable dans la page" if json.nil?

    JSON.parse(CGI.unescapeHTML(json))[lodging.id.to_s]
  end

  it "laisse les nuits libres quand la demande concurrente est seulement EN ATTENTE" do
    occupe("pending")
    composer

    expect(response).to have_http_status(:ok)
    expect(disponibilites_pour(hulotte)).to eq([true, true])
  end

  it "grise les nuits tenues par une demande PRÉ-CONFIRMÉE" do
    occupe("pre_confirmed")
    composer

    expect(response).to have_http_status(:ok)
    expect(disponibilites_pour(hulotte)).to eq([false, false])
  end

  it "rend les nuits dès que le pré-confirmé repasse en attente" do
    booking = occupe("pre_confirmed")
    composer
    expect(disponibilites_pour(hulotte)).to eq([false, false])

    booking.update!(status: "pending")
    composer

    expect(disponibilites_pour(hulotte)).to eq([true, true])
  end
end
