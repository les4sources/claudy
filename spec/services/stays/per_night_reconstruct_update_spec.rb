require "rails_helper"

# Round-trip grille → bookings → grille (DraftReconstructor) et recomposition des
# plages à l'édition (AdminUpdater), pour le camping/van par nuit (Michael 2026-07-20).
RSpec.describe "Camping/van par nuit — reconstruction & édition" do
  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 34 } # 4 nuits

  def build_stay(pnr)
    draft = Reservations::Draft.new(
      arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      dogs_count: 0, first_name: "Alice", last_name: "Martin",
      email: "alice@example.com", phone: "0470111222",
      per_night_resources: pnr
    )
    Reservations::Builder.new(draft: draft, admin: true, source: "manual").tap(&:run!).stay
  end

  describe "Stays::DraftReconstructor" do
    it "reconstitue fidèlement per_night_resources depuis les N bookings" do
      stay = build_stay("tente" => %w[2 2 0 3], "van" => %w[0 1 1 0])
      pnr  = Stays::DraftReconstructor.call(stay).per_night_resources

      expect(pnr["tente"]).to eq(%w[2 2 0 3])
      expect(pnr["van"]).to eq(%w[0 1 1 0])
    end

    it "round-trip : grille → bookings → grille → mêmes bookings" do
      stay1 = build_stay("tente" => %w[3 0 3 3])
      draft = Stays::DraftReconstructor.call(stay1)

      # La grille reconstruite doit reproduire les MÊMES plages.
      ranges = draft.campings # dérivées de per_night_resources
      # 3 nuits actives (idx 0, 2, 3), une entrée per-nuit (contrat pricing).
      expect(ranges.map { |r| r[:people] }).to eq([3, 3, 3])
    end
  end

  describe "Stays::AdminUpdater — édition d'une nuit" do
    it "recompose les plages sans perte quand une nuit change" do
      stay = build_stay("tente" => %w[2 2 2 2]) # 1 plage au départ
      expect(stay.stay_items.where(bookable_type: "CampingBooking").count).to eq(1)

      # On creuse la nuit 3 à 0 → doit produire 2 plages (nuits 1-2 et nuit 4).
      new_draft = Reservations::Draft.new(
        arrival_date: arrival.iso8601, departure_date: departure.iso8601,
        dogs_count: 0, first_name: "Alice", last_name: "Martin",
        email: "alice@example.com", phone: "0470111222",
        per_night_resources: { "tente" => %w[2 2 0 2] }
      )
      updater = Stays::AdminUpdater.new(stay: stay, draft: new_draft)
      expect(updater.run).to be(true)

      campings = stay.reload.stay_items.where(bookable_type: "CampingBooking")
                     .filter_map(&:bookable).sort_by(&:from_date)
      expect(campings.size).to eq(2)
      expect(campings[0].from_date).to eq(arrival)
      expect(campings[0].to_date).to eq(arrival + 2)
      expect(campings[1].from_date).to eq(arrival + 3)
      expect(campings[1].to_date).to eq(arrival + 4)
      # Invariant prix : ∑ plages == part camping du devis recalculé.
      expect(campings.sum(&:price_cents)).to eq(new_draft.quote.camping_cents)
      # Total du séjour cohérent (aucune plage perdue).
      expect(stay.total_amount_cents).to eq(new_draft.quote.total_excluding_experiences_cents)
    end
  end
end
