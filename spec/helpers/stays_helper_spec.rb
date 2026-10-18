require "rails_helper"

# L'heure d'arrivée dans le déroulé du séjour (Michael, 2026-08-19).
#
# Elle vient de deux endroits — celle qu'on note en interne et celle que le
# client annonce depuis sa page — et c'est la seconde qui manquait à l'écran :
# 286 réservations en portent une, et la personne qui accueille ne la voyait
# nulle part.
RSpec.describe StaysHelper, type: :helper do
  let(:customer) { Customer.create!(email: "heure@example.com", customer_type: "individual") }
  let(:arrivee) { Date.today + 30 }
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: arrivee, departure_date: arrivee + 2)
  end

  def reserve(estimated_arrival: nil, lodging: nil)
    booking = Booking.create!(firstname: "Client", adults: 2, from_date: arrivee, to_date: arrivee + 2,
                              estimated_arrival: estimated_arrival, lodging: lodging)
    StayItem.create!(stay: stay, bookable: booking)
    booking
  end

  def arrivee_jalon = helper.stay_timeline(stay.decorate).first

  it "n'affiche aucune heure quand rien n'est renseigné" do
    reserve

    expect(arrivee_jalon[:title]).to include("Arrivée")
    expect(arrivee_jalon[:title]).not_to include("·")
    expect(arrivee_jalon[:note]).to be_nil
  end

  it "porte au titre l'heure annoncée par le client quand elle est courte" do
    reserve(estimated_arrival: "16h")

    expect(arrivee_jalon[:title]).to include("· 16h — Arrivée")
    expect(arrivee_jalon[:note]).to be_nil
  end

  it "accepte une fourchette, qui reste courte" do
    reserve(estimated_arrival: "16-18h")

    expect(arrivee_jalon[:title]).to include("· 16-18h")
  end

  # Tronquer serait pire que déplacer : c'est la fin de la phrase qui porte la
  # raison, donc l'information utile à l'accueil.
  it "descend une phrase sous le titre au lieu de la tronquer" do
    reserve(estimated_arrival: "Après 18h car ils s'installent d'abord à leur évènement")

    expect(arrivee_jalon[:title]).not_to include("Après 18h")
    expect(arrivee_jalon[:note]).to eq("Arrivée annoncée : Après 18h car ils s'installent d'abord à leur évènement")
  end

  it "préfère l'heure notée en interne, et garde l'annonce du client en dessous" do
    stay.update!(arrival_time: "14h")
    reserve(estimated_arrival: "16h")

    expect(arrivee_jalon[:title]).to include("· 14h")
    expect(arrivee_jalon[:note]).to eq("Arrivée annoncée : 16h")
  end

  # Deux gîtes, deux heures : les afficher toutes, sans doublon.
  it "réunit les heures de plusieurs réservations sans les répéter" do
    reserve(estimated_arrival: "16h")
    reserve(estimated_arrival: "16h")
    reserve(estimated_arrival: "21h")

    expect(arrivee_jalon[:title]).to include("· 16h")
    expect(arrivee_jalon[:note]).to eq("Arrivée annoncée : 21h")
  end

  it "affiche l'heure de départ notée en interne" do
    stay.update!(departure_time: "10h30")
    reserve

    depart = helper.stay_timeline(stay.decorate).last
    expect(depart[:title]).to include("· 10h30 — Départ")
  end

  it "garde le lieu sous le titre, à côté de l'heure" do
    gite = Lodging.create!(name: "La Chevêche")
    reserve(estimated_arrival: "16h", lodging: gite)

    expect(arrivee_jalon[:detail]).to eq("La Chevêche")
  end

  # Séjour d'une journée (Michael, 2026-10-18) : arrivée et départ le même jour
  # ne font plus deux lignes qui répètent la date.
  describe "séjour sur une seule journée" do
    let(:stay) do
      Stay.create!(customer: customer, source: "manual", status: "confirmed",
                   arrival_date: arrivee, departure_date: arrivee,
                   arrival_time: "9h30", departure_time: "14h")
    end

    def deroule = helper.stay_timeline(stay.decorate)

    it "dit la date une seule fois, avec la plage horaire" do
      expect(deroule.size).to eq(1)
      expect(deroule.first[:title]).to eq("#{I18n.l(arrivee, format: :long).capitalize} · 9h30 → 14h")
      expect(deroule.first[:title]).not_to include("Départ")
    end

    it "garde l'heure de départ seule quand l'arrivée n'en a pas" do
      stay.update!(arrival_time: nil)

      expect(deroule.first[:title]).to end_with("· jusqu'à 14h")
    end

    it "nomme la salle occupée" do
      salle = Space.create!(name: "Grande Salle", capacity: 1)
      booking = SpaceBooking.create!(firstname: "Client", from_date: arrivee, to_date: arrivee)
      SpaceReservation.create!(space_booking: booking, space: salle, date: arrivee)
      StayItem.create!(stay: stay, bookable: booking)

      expect(deroule.first[:detail]).to eq("Grande Salle")
    end

    it "range activités et repas sous la journée, avec leur heure seule" do
      MealOrder.create!(stay: stay, kind: "repas", moment: "midi", date: arrivee, people: 12,
                        status: "requested", skip_notifications: true)
      experience = Experience.create!(name: "Balade avec les ânes")
      creneau = ExperienceAvailability.create!(experience: experience, available_on: arrivee, starts_at: "10:30")
      ExperienceBooking.create!(experience_availability: creneau, stay: stay, participants: 8)

      expect(deroule.map { |j| j[:title] }).to eq([
        "#{I18n.l(arrivee, format: :long).capitalize} · 9h30 → 14h",
        "10h30 — Balade avec les ânes",
        "Repas (midi)"
      ])
    end
  end
end
