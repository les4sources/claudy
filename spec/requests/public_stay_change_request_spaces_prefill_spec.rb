require "rails_helper"

# Epic #234, Phase 3 — le formulaire « Modifier mon séjour » ouvrait sa grille
# ESPACES VIDE : le séjour reconstruit rend des lignes `halls`, la grille lit
# `space_slots`, et personne ne faisait la conversion de ce côté (l'admin, lui,
# la faisait depuis la phase 1). Conséquence : un client qui déplaçait ses dates
# soumettait une demande SANS ses salles, et l'approbation les effaçait.
RSpec.describe "Modification client — préremplissage de la grille Espaces (epic #234, Phase 3)", type: :request do
  let(:customer) { Customer.create!(first_name: "Ana", last_name: "Lopez", email: "ana-espaces@example.com") }
  let!(:lodging) { Lodging.find_or_create_by!(name: "La Hulotte") { |l| l.price_night_cents = 48_500 } }
  let!(:petite_salle) { Space.create!(name: "Petite Salle", code: "SAU", capacity: 1) }

  # Ancré sur un lundi : le barème des salles distingue semaine et week-end.
  let(:lundi)    { (Date.current + 30).next_occurring(:monday) }
  let(:vendredi) { lundi + 4 }

  let(:stay) do
    s = Stay.create!(customer: customer, source: "manual", status: "confirmed",
                     arrival_date: lundi, departure_date: vendredi,
                     total_amount_cents: 200_000)
    booking = Booking.create!(firstname: "Ana", lastname: "Lopez", email: "ana-espaces@example.com",
                              from_date: lundi, to_date: vendredi, adults: 2,
                              status: "confirmed", price_cents: 134_500, lodging: lodging)
    s.stay_items.create!(bookable: booking)

    sb = SpaceBooking.create!(firstname: "Ana", lastname: "Lopez", email: "ana-espaces@example.com",
                              from_date: lundi, to_date: vendredi, status: "confirmed")
    (lundi..vendredi).each do |date|
      SpaceReservation.create!(space_booking: sb, space: petite_salle, date: date, duration: "day")
    end
    s.stay_items.create!(bookable: sb)
    s
  end

  it "rend la grille préremplie des 5 journées déjà réservées" do
    get new_public_stay_change_request_path(stay.token)

    valeurs = Nokogiri::HTML(response.body)
                      .css(%(input[name="reservation[space_slots][petite_salle][]"]))
                      .map { |i| i["value"] }

    expect(valeurs).to eq(%w[journee journee journee journee journee])
  end

  it "dit en clair ce qui est réservé, sous la grille" do
    get new_public_stay_change_request_path(stay.token)

    ligne = Nokogiri::HTML(response.body).at_css(%([data-summary-for="petite_salle"]))

    expect(ligne["class"].to_s).not_to include("hidden")
    expect(ligne.text.gsub(/\s+/, " ").strip)
      .to eq("Petite Salle · 5 journées · lun #{lundi.strftime('%-d')} → ven #{vendredi.strftime('%-d')}")
  end

  # Le delta se calcule entre deux recotes du MÊME barème. La référence doit
  # donc être dans la même représentation que ce que le formulaire soumet,
  # sinon un formulaire intact affiche un écart qui n'existe pas.
  it "n'invente aucun écart sur un formulaire intact" do
    get new_public_stay_change_request_path(stay.token)

    expect(response.body).to include("Votre nouveau devis")
    totaux = response.body.scan(/Total actuel<\/span><span>([^<]+)/).flatten +
             response.body.scan(/Nouveau total<\/span><span>([^<]+)/).flatten
    expect(totaux.uniq.size).to eq(1)
  end
end
