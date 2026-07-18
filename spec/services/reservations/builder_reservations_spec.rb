require "rails_helper"

# ---------------------------------------------------------------------------
# Epic #66, Phase 6 (correctif) — le Builder crée les Reservation de chambres de
# l'occupation d'hébergement. Sans elles, le séjour était INVISIBLE au calendrier
# (rendu par chambre, Phase 4) et le veto `Lodging#available_between?` (qui compte
# les Reservation confirmées) ne se posait jamais → surbooking silencieux.
#
# La création a lieu dans TOUS les canaux (admin ET funnel public natif). Le veto
# reste piloté par le statut `confirmed` : un séjour pending est visible au
# calendrier mais ne bloque pas la dispo ; un séjour confirmed pose le veto.
# ---------------------------------------------------------------------------
RSpec.describe Reservations::Builder, "occupation room-based (epic #66, Phase 6)" do
  # Hébergement avec DEUX chambres, pour vérifier N = chambres × nuits.
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging.rooms << Room.create!(name: "Chambre 2", level: 1)
    lodging
  end

  let(:arrival) { Date.today + 30 }    # 2 nuits : [arrival, arrival+2)
  let(:departure) { Date.today + 32 }

  def draft(**overrides)
    Reservations::Draft.new({
      lodging_id: hulotte.id,
      arrival_date: arrival.iso8601,
      departure_date: departure.iso8601,
      dogs_count: 0,
      first_name: "Camille",
      last_name: "Martin",
      email: "camille@example.com",
      phone: "+32470112233"
    }.merge(overrides))
  end

  describe "création des Reservation de chambres" do
    it "crée N Reservation = (chambres du lodging) × (nuits) sur [arrivée, départ)" do
      builder = described_class.new(draft: draft, admin: true, status: "confirmed", source: "manual")
      expect(builder.run!).to be(true)

      booking = builder.booking
      # 2 chambres × 2 nuits = 4 Reservation.
      expect(booking.reservations.count).to eq(4)
      expect(booking.reservations.map(&:room_id).uniq).to match_array(hulotte.rooms.pluck(:id))
      # Nuits [arrival, departure) — le jour du départ n'est PAS occupé.
      expect(booking.reservations.map(&:date).uniq).to match_array([arrival, arrival + 1])
      expect(booking.reservations.map(&:date)).not_to include(departure)
    end

    it "ne modifie pas le prix du Booking (invariant Phase 3 préservé)" do
      builder = described_class.new(draft: draft, admin: true, status: "confirmed", source: "manual")
      before = builder.quote.lodging_only_cents
      builder.run!
      expect(builder.booking.price_cents).to eq(before)
      expect(builder.booking.shown_price_cents).to eq(before)
    end
  end

  describe "veto de disponibilité piloté par le statut confirmed" do
    it "un séjour CONFIRMED rend le lodging indisponible sur la fenêtre chevauchante" do
      described_class.new(draft: draft, admin: true, status: "confirmed", source: "manual").run!

      expect(hulotte.available_between?(arrival, departure)).to be(false)
      # Hors chevauchement : toujours disponible.
      expect(hulotte.available_between?(departure + 5, departure + 7)).to be(true)
    end

    it "un séjour PENDING crée bien ses Reservation (visible calendrier) mais NE pose PAS le veto" do
      builder = described_class.new(draft: draft, admin: true, status: "pending", source: "manual")
      builder.run!

      expect(builder.booking.reservations.count).to eq(4)   # visible au calendrier
      expect(builder.booking.status).to eq("pending")
      expect(hulotte.available_between?(arrival, departure)).to be(true) # pas de veto
    end
  end

  describe "canal public natif (admin: false)" do
    it "crée AUSSI les Reservation de chambres (statut pending, jamais d'auto-confirm)" do
      builder = described_class.new(draft: draft) # public : admin false par défaut
      expect(builder.run).to be(true)

      expect(builder.booking.status).to eq("pending")
      expect(builder.booking.reservations.count).to eq(4)
      # Pending → visible calendrier mais pas de veto (cohérent avec le public).
      expect(hulotte.available_between?(arrival, departure)).to be(true)
    end
  end
end
