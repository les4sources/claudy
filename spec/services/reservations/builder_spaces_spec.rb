require "rails_helper"

# Epic #66, Phase 2 — Espaces dans la composition du séjour. Le Builder persiste
# désormais les espaces choisis (halls / space_slots) en un SpaceBooking +
# StayItem, y compris pour un séjour « espaces seuls » (sans hébergement). La part
# espaces vit sur le SpaceBooking ; l'hébergement porte le reste (aucun double-compte).
RSpec.describe Reservations::Builder, "espaces (epic #66, Phase 2)" do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end
  # Grande Salle → grande_salle (grille de pricing). Capacity 1 = salle exclusive.
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }

  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 32 }
  # grande_salle / journée (barème semaine des salles) = 290 €.
  let(:grande_salle_journee_cents) { 29_000 }
  let(:hulotte_two_nights_cents)   { 74_500 }

  def draft(**overrides)
    Reservations::Draft.new({
      lodging_id: hulotte.id,
      arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470112233"
    }.merge(overrides))
  end

  def hall(date: nil, kind: "grande_salle", period: "journee")
    { kind: kind, date: (date || arrival).iso8601, period: period }
  end

  describe "hébergement + espace" do
    it "crée un SpaceBooking + StayItem et ventile le prix sans double-compte" do
      builder = described_class.new(draft: draft(halls: [hall]), admin: true, source: "manual")
      expect(builder.run).to be(true)

      sb = builder.space_booking
      expect(sb).to be_persisted
      expect(builder.stay.stay_items.map(&:bookable)).to include(sb)
      expect(sb.space_reservations.map(&:space)).to eq([grande_salle])
      expect(sb.price_cents).to eq(grande_salle_journee_cents)

      # Le Booking d'hébergement porte le reste (hors espaces) — pas de double-compte.
      expect(builder.booking.price_cents).to eq(hulotte_two_nights_cents)
      # Total prévu = hébergement + espace.
      expect(builder.stay.total_amount_cents).to eq(hulotte_two_nights_cents + grande_salle_journee_cents)
      # recompute redonne exactement le même total (Booking + SpaceBooking).
      builder.stay.recompute_aggregates!
      expect(builder.stay.reload.total_amount_cents).to eq(hulotte_two_nights_cents + grande_salle_journee_cents)
    end
  end

  # Bug 2026-07-20 : la salle demandée « le 22, journée » était persistée sur la
  # fenêtre du séjour (21→23) avec la période de PRICING brute ("journee"), que
  # l'affichage (vocabulaire tranche 1) traduit… « période non précisée ».
  describe "dates réelles + vocabulaire canonique de durée" do
    it "persiste la durée CANONIQUE (day/evening/fullday), jamais la clé de pricing" do
      builder = described_class.new(
        draft: draft(halls: [hall(period: "journee"),
                             hall(date: arrival + 1, period: "soiree"),
                             hall(date: arrival + 2, period: "journee_et_soiree")]),
        admin: true, source: "manual"
      )
      expect(builder.run).to be(true)

      durations = builder.space_booking.space_reservations.order(:date).map(&:duration)
      expect(durations).to eq(%w[day evening fullday])
      # Le décorateur (source des libellés partout) sait donc les afficher.
      decorated = SpaceBookingDecorator.new(builder.space_booking)
      expect(decorated.duration).not_to include("non précisée")
    end

    it "borne from/to_date aux dates RÉELLEMENT occupées, pas à la fenêtre du séjour" do
      middle_day = arrival + 1
      builder = described_class.new(
        draft: draft(halls: [hall(date: middle_day)]), admin: true, source: "manual"
      )
      expect(builder.run).to be(true)

      sb = builder.space_booking
      expect(sb.from_date).to eq(middle_day)
      expect(sb.to_date).to eq(middle_day)
    end

    it "aller-retour édition : le DraftReconstructor re-mappe la durée en clé de pricing" do
      builder = described_class.new(draft: draft(halls: [hall(period: "journee")]),
                                    admin: true, source: "manual")
      expect(builder.run).to be(true)

      rebuilt = Stays::DraftReconstructor.new(builder.stay.reload).to_draft
      expect(rebuilt.halls.first[:period]).to eq("journee")
      # …et le devis d'édition retrouve son tarif (290 € — pas un 0 silencieux).
      expect(rebuilt.quote.spaces_cents).to eq(grande_salle_journee_cents)
    end
  end

  describe "séjour « espaces seuls » (sans hébergement)" do
    let(:spaces_only) { draft(lodging_id: nil, halls: [hall]) }

    it "ne crée AUCUN Booking mais persiste le SpaceBooking en StayItem" do
      builder = described_class.new(draft: spaces_only, admin: true, source: "manual")
      expect(builder.run).to be(true)

      expect(builder.booking).to be_nil
      sb = builder.space_booking
      expect(sb).to be_persisted
      expect(builder.stay.stay_items.map(&:bookable)).to eq([sb])
      expect(builder.stay.total_amount_cents).to eq(grande_salle_journee_cents)
      expect(builder.stay.arrival_date).to eq(arrival)
      expect(builder.stay.departure_date).to eq(departure)
    end

    it "garde des agrégats corrects après recompute (dates non écrasées à nil)" do
      builder = described_class.new(draft: spaces_only, admin: true, source: "manual")
      builder.run
      stay = builder.stay

      stay.recompute_aggregates!
      stay.reload
      expect(stay.total_amount_cents).to eq(grande_salle_journee_cents)
      # Depuis le fix 2026-07-20, le SpaceBooking porte ses dates RÉELLES (le
      # seul jour de salle réservé), plus la fenêtre saisie du séjour : le
      # recompute d'un séjour espaces-seuls s'aligne donc sur la salle.
      expect(stay.arrival_date).to eq(arrival)
      expect(stay.departure_date).to eq(arrival)
    end
  end

  describe "disponibilité capacity-aware des espaces" do
    def occupy_grande_salle!(date)
      sb = SpaceBooking.create!(firstname: "Occ", from_date: date, to_date: date, status: "confirmed")
      sb.space_reservations.create!(space: grande_salle, date: date, duration: "journee")
    end

    it "bloque un espace déjà complet hors force" do
      occupy_grande_salle!(arrival)
      builder = described_class.new(draft: draft(lodging_id: nil, halls: [hall]), admin: true, source: "manual")

      expect(builder.run).to be(false)
      expect(builder.error_message).to match(/complet/i)
      expect(Stay.count).to eq(0)
    end

    it "force la création avec un avertissement" do
      occupy_grande_salle!(arrival)
      builder = described_class.new(
        draft: draft(lodging_id: nil, halls: [hall]), admin: true, source: "manual", skip_availability: true
      )

      expect(builder.run).to be(true)
      expect(builder.availability_warning).to match(/forçant la disponibilité/i)
      expect(builder.space_booking).to be_persisted
    end
  end
end
