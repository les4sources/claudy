require "rails_helper"

# Décision Michael du 2026-09-08 : une demande PRÉ-CONFIRMÉE tient ses dates.
# Jusqu'ici seul `confirmed` posait le veto, ce qui laissait pré-confirmer deux
# demandes sur le même gîte aux mêmes dates puis les confirmer toutes les deux.
#
# Ces exemples verrouillent la SOURCE UNIQUE (`Stay::BLOCKING_STATUSES`) là où
# elle compte : la dispo d'un gîte, celle d'un sous-ensemble de chambres, celle
# d'un espace, et les capacités globales du plein air.
RSpec.describe "Statuts bloquants du calendrier" do
  let(:hulotte) { Lodging.create!(name: "La Hulotte", price_night_cents: 10_000) }
  let(:chambre_a) { Room.create!(name: "Chambre A", level: 1) }
  let(:chambre_b) { Room.create!(name: "Chambre B", level: 1) }

  let(:arrivee) { Date.new(2026, 10, 5) }
  let(:depart)  { Date.new(2026, 10, 9) }

  before do
    hulotte.rooms << chambre_a
    hulotte.rooms << chambre_b
  end

  # Occupe TOUTES les chambres du gîte sur les nuits [from, to).
  def occuper(status:, rooms: hulotte.rooms, from: arrivee, to: depart)
    booking = Booking.create!(firstname: "Occ", from_date: from, to_date: to,
                              adults: 2, status: status, lodging: hulotte)
    rooms.each do |room|
      (from...to).each { |date| Reservation.create!(booking: booking, room: room, date: date) }
    end
    booking
  end

  describe "Lodging#available_between?" do
    it "reste disponible face à une demande simplement EN ATTENTE" do
      occuper(status: "pending")

      expect(hulotte.available_between?(arrivee, depart)).to be(true)
    end

    it "devient indisponible face à un séjour CONFIRMÉ (comportement historique)" do
      occuper(status: "confirmed")

      expect(hulotte.available_between?(arrivee, depart)).to be(false)
    end

    # Le cœur de la décision du 2026-09-08.
    it "devient indisponible face à un séjour PRÉ-CONFIRMÉ" do
      occuper(status: "pre_confirmed")

      expect(hulotte.available_between?(arrivee, depart)).to be(false)
    end

    it "libère les dates quand le pré-confirmé retombe en attente" do
      booking = occuper(status: "pre_confirmed")
      expect(hulotte.available_between?(arrivee, depart)).to be(false)

      booking.update!(status: "pending")

      expect(hulotte.reload.available_between?(arrivee, depart)).to be(true)
    end

    it "libère les dates quand le pré-confirmé est annulé" do
      booking = occuper(status: "pre_confirmed")

      booking.update!(status: "canceled")

      expect(hulotte.reload.available_between?(arrivee, depart)).to be(true)
    end

    # Rotation dos-à-dos : le jour de DÉPART n'est pas occupé (contrat issue
    # #94). Le passage aux statuts bloquants ne doit pas l'avoir cassé.
    it "laisse une arrivée le jour du départ d'un pré-confirmé" do
      occuper(status: "pre_confirmed")

      expect(hulotte.available_between?(depart, depart + 2)).to be(true)
    end
  end

  describe "Lodging#rooms_available_between? (chambres seules)" do
    it "refuse une chambre tenue par un pré-confirmé" do
      occuper(status: "pre_confirmed", rooms: [chambre_a])

      expect(hulotte.rooms_available_between?([chambre_a.id], arrivee, depart)).to be(false)
      # L'autre chambre reste libre : le veto est bien borné aux chambres prises.
      expect(hulotte.rooms_available_between?([chambre_b.id], arrivee, depart)).to be(true)
    end
  end

  describe "Lodging#booked_on?" do
    it "compte un pré-confirmé comme une occupation" do
      occuper(status: "pre_confirmed")

      expect(hulotte.booked_on?(arrivee)).to be(true)
    end
  end

  describe "Space#available_on?" do
    let(:salle) { Space.create!(name: "Grande Salle", capacity: 1) }

    def occuper_salle(status:)
      sb = SpaceBooking.create!(firstname: "Occ", from_date: arrivee, to_date: arrivee,
                                status: status)
      SpaceReservation.create!(space_booking: sb, space: salle, date: arrivee, duration: "day")
      sb
    end

    it "reste disponible face à une demande en attente" do
      occuper_salle(status: "pending")

      expect(salle.available_on?(arrivee)).to be(true)
    end

    it "devient indisponible face à un pré-confirmé" do
      occuper_salle(status: "pre_confirmed")

      expect(salle.available_on?(arrivee)).to be(false)
    end
  end

  describe "capacités globales du plein air" do
    it "compte les CampingBooking pré-confirmés contre la capacité" do
      CampingBooking.create!(kind: "tente", people: CampingBooking.total_capacity,
                             from_date: arrivee, to_date: depart, status: "pre_confirmed")

      expect(CampingBooking.remaining_on(arrivee)).to eq(0)
      expect(CampingBooking.capacity_conflict_date(units: 1, from: arrivee, to: depart)).to eq(arrivee)
    end

    it "compte les VanBooking pré-confirmés contre la capacité" do
      VanBooking.create!(vehicles: VanBooking.total_capacity,
                         from_date: arrivee, to_date: depart, status: "pre_confirmed")

      expect(VanBooking.remaining_on(arrivee)).to eq(0)
    end

    it "compte les HamacBooking pré-confirmés contre le stock" do
      RentalItem.create!(name: HamacBooking::RENTAL_ITEM_NAMES["simple"], stock: 2)
      HamacBooking.create!(kind: "simple", count: 2, from_date: arrivee, to_date: depart,
                           status: "pre_confirmed")

      expect(HamacBooking.remaining_on("simple", arrivee)).to eq(0)
    end
  end
end
