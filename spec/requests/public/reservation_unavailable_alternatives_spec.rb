require "rails_helper"

# Sortie de secours sur une nuit indisponible (2026-07-29).
#
# La mini-modale « hébergement indisponible » se contentait de constater le
# refus : le client lisait « La Hulotte n'est pas libre le 10 novembre » et
# n'avait aucune piste — alors que le gîte voisin est souvent libre pour
# exactement les mêmes nuits. Chaque cellule indisponible porte désormais la
# liste des autres gîtes libres CETTE nuit-là, lue depuis `@lodging_availability`
# déjà calculé pour la grille : aucune requête supplémentaire.
RSpec.describe "Public::Reservations — alternatives sur nuit indisponible", type: :request do
  let!(:hulotte) do
    l = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    l.rooms << Room.create!(name: "Chambre H", level: 1)
    l
  end
  let!(:cheveche) do
    l = Lodging.create!(name: "La Chevêche", price_night_cents: 40_000)
    l.rooms << Room.create!(name: "Chambre C", level: 1)
    l
  end

  let(:arrival)   { Date.today + 100 }
  let(:departure) { Date.today + 102 }

  def occupe(lodging)
    b = Booking.create!(firstname: "Occ", from_date: arrival, to_date: departure, adults: 1, status: "confirmed")
    (arrival...departure).each { |d| Reservation.create!(booking: b, room: lodging.rooms.first, date: d) }
  end

  def compose
    post "/reservation/sejour", params: {
      reservation: { arrival_date: arrival.iso8601, departure_date: departure.iso8601, adults: 2 }
    }
    get "/reservation/composer"
  end

  it "propose le gîte encore libre quand l'autre est pris" do
    occupe(hulotte)
    compose

    expect(response).to have_http_status(:ok)
    # L'attribut est du JSON échappé dans le HTML ; on vérifie la présence du nom.
    alternatives = response.body.scan(/data-unavail-alternatives="([^"]*)"/).flatten
    expect(alternatives).not_to be_empty
    expect(alternatives.first).to include("Chev")
    expect(alternatives.first).not_to include("Hulotte")
  end

  it "ne propose rien quand tout est pris" do
    occupe(hulotte)
    occupe(cheveche)
    compose

    alternatives = response.body.scan(/data-unavail-alternatives="([^"]*)"/).flatten
    expect(alternatives).not_to be_empty
    expect(alternatives).to all(eq("[]"))
  end

  it "ne pose l'attribut que sur les cellules indisponibles" do
    occupe(hulotte)
    compose

    # Autant d'attributs que de cellules « — », pas une de plus.
    indispo = response.body.scan(/funnel-night-cell funnel-night-cell--off/).size
    attributs = response.body.scan(/data-unavail-alternatives=/).size
    expect(attributs).to eq(indispo)
  end
end
