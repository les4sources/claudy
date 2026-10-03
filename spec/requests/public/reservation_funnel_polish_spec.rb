require "rails_helper"

# Finitions du funnel /reservation (Michael, 2026-10-03).
RSpec.describe "Public::Reservations — finitions du funnel", type: :request do
  include ActiveJob::TestHelper

  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500, summary: "9 à 16 personnes")
    2.times { |i| l.rooms << Room.create!(name: "Chambre #{i}", level: 1) }
    l.rooms << Room.create!(name: "Laurier (mezzanine)", code: "MEZ", level: 2)
    l
  end

  let(:arrival)   { Date.new(Date.today.year + 1, 3, 10) }
  let(:departure) { arrival + 1 }

  def compose
    post "/reservation/sejour", params: {
      reservation: { arrival_date: arrival.iso8601, departure_date: departure.iso8601, adults: 2 }
    }
    get "/reservation/composer"
  end

  it "écrit l'année une seule fois pour un séjour dans la même année" do
    compose
    expect(response.body).to include("#{arrival.day} mars → #{departure.day} mars #{arrival.year}")
  end

  it "ne compte pas la mezzanine comme une chambre" do
    compose
    expect(response.body).to include("9 à 16 personnes · 2 chambres")
    expect(response.body).not_to include("3 chambres")
  end

  it "dit l'état de chaque nuit en toutes lettres" do
    b = Booking.create!(firstname: "Occ", from_date: arrival, to_date: departure, adults: 1, status: "confirmed")
    hulotte.rooms.each { |r| Reservation.create!(booking: b, room: r, date: arrival) }
    compose

    expect(response.body).to include("Complet")
    expect(response.body).to include("Complet à vos dates")
  end

  it "ne montre plus ni prix ni bûches dans la grille nuit par nuit" do
    compose
    grille = response.body[/data-controller="public--stay-calendar[^"]*".*?<\/table>/m]
    expect(grille).to be_present
    expect(grille).not_to match(/dès\s+\d+\s*€\/nuit/)
  end

  it "affiche les trois offres « Repas & pain » et le catalogue des activités" do
    compose
    expect(response.body).to include("Repas sur demande")
    expect(response.body).to include("15 € par personne")
    expect(response.body).to include("Épicerie sur place")
    expect(response.body).to include("https://tranchesdevie.les4sources.be")
    expect(response.body).to include('name="reservation[activities_note]"')
    expect(response.body).not_to include("Nuitée individuelle")
    expect(response.body).not_to include("pain &amp; épicerie")
  end

  it "ne met plus d'espace à l'intérieur du lien email de l'étape 1" do
    get "/reservation/sejour"
    expect(response.body).not_to include("> sejours@les4sources.be</a>")
    expect(response.body).not_to include("Nuitée individuelle en semaine")
  end

  it "transmet les activités souhaitées avec la demande" do
    perform_enqueued_jobs do
      post "/reservation/coordonnees", params: {
        reservation: {
          arrival_date: arrival.iso8601, departure_date: departure.iso8601,
          dogs_count: 0, first_name: "Act", email: "act@example.com", phone: "+32 470 11 12 13",
          lodging_night_ids: [hulotte.id],
          activities_note: "Balade avec les ânes pour 6 enfants"
        }
      }
    end

    stay = Stay.last
    expect(stay).to be_present
    expect(stay.internal_notes.to_plain_text).to include("Activités qui intéressent le groupe : Balade avec les ânes pour 6 enfants")
  end

  it "refuse un numéro de téléphone qui n'en est pas un" do
    expect {
      post "/reservation/coordonnees", params: {
        reservation: {
          arrival_date: arrival.iso8601, departure_date: departure.iso8601,
          first_name: "Tel", email: "tel@example.com", phone: "appelez-moi",
          lodging_night_ids: [hulotte.id]
        }
      }
    }.not_to change(Stay, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Ce numéro ne semble pas complet")
  end
end
