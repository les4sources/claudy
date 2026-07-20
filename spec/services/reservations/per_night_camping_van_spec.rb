require "rails_helper"

# Camping / van « une nuit du séjour » (Michael 2026-07-20) : la grille par nuit
# `per_night_resources` est PERSISTÉE honnêtement en N réservables, un par PLAGE
# CONTIGUË de valeur constante non nulle. Invariant de prix : ∑ plages == part
# camping/van du devis. Repli inchangé sur la représentation pleine-fenêtre.
RSpec.describe "Persistance camping/van par nuit (plages contiguës)" do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  let(:arrival)   { Date.today + 30 }
  let(:departure) { Date.today + 34 } # 4 nuits

  def draft(**overrides)
    Reservations::Draft.new({
      arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470112233"
    }.merge(overrides))
  end

  describe "Reservations::Builder — grille [2,2,0,3]" do
    let(:grid_draft) { draft(per_night_resources: { "tente" => %w[2 2 0 3] }) }

    it "crée 2 plages aux bonnes dates/people, ∑ prix == quote.camping_cents" do
      builder = Reservations::Builder.new(draft: grid_draft)
      expect(builder.run).to be(true)

      campings = builder.stay.stay_items.where(bookable_type: "CampingBooking")
                        .filter_map(&:bookable).sort_by(&:from_date)
      expect(campings.size).to eq(2)

      # Plage 1 : nuits 1-2 (arrivée, arrivée+2 exclu), 2 personnes.
      expect(campings[0].from_date).to eq(arrival)
      expect(campings[0].to_date).to eq(arrival + 2)
      expect(campings[0].people).to eq(2)
      expect(campings[0].price_cents).to eq(750 * 2 * 2) # 3 000 c

      # Plage 2 : nuit 4 uniquement, 3 personnes.
      expect(campings[1].from_date).to eq(arrival + 3)
      expect(campings[1].to_date).to eq(arrival + 4)
      expect(campings[1].people).to eq(3)
      expect(campings[1].price_cents).to eq(750 * 3 * 1) # 2 250 c

      # Invariant : la somme des plages == la part camping du devis.
      expect(campings.sum(&:price_cents)).to eq(grid_draft.quote.camping_cents)
    end

    it "n'ampute jamais le total du séjour (ventilation exhaustive)" do
      builder = Reservations::Builder.new(draft: grid_draft)
      builder.run
      stay = builder.stay
      parts = stay.bookables.sum { |b| b.try(:price_cents).to_i } +
              stay.meal_orders.sum(:price_cents)
      expect(parts).to eq(stay.total_amount_cents)
    end
  end

  describe "Reservations::Builder — grille van [0,1,1,0]" do
    it "crée une plage van sur les nuits 2-3, ∑ prix == quote.van_cents" do
      d = draft(per_night_resources: { "van" => %w[0 1 1 0] })
      builder = Reservations::Builder.new(draft: d)
      expect(builder.run).to be(true)

      vans = builder.stay.stay_items.where(bookable_type: "VanBooking").filter_map(&:bookable)
      expect(vans.size).to eq(1)
      expect(vans.first.from_date).to eq(arrival + 1)
      expect(vans.first.to_date).to eq(arrival + 3)
      expect(vans.first.vehicles).to eq(1)
      expect(vans.sum(&:price_cents)).to eq(d.quote.van_cents)
    end
  end

  describe "grille absente — comportement historique intact" do
    it "persiste UN camping pleine-fenêtre depuis campings: [{people, nights}]" do
      d = draft(campings: [{ kind: "tente", people: 4, nights: 4 }])
      builder = Reservations::Builder.new(draft: d)
      expect(builder.run).to be(true)

      campings = builder.stay.stay_items.where(bookable_type: "CampingBooking").filter_map(&:bookable)
      expect(campings.size).to eq(1)
      expect(campings.first.people).to eq(4)
      expect(campings.first.from_date).to eq(arrival)
      expect(campings.first.to_date).to eq(departure)
      expect(campings.first.price_cents).to eq(d.quote.camping_cents)
    end
  end
end

# Revue Forge F1/F4 — durcissements.
RSpec.describe Reservations::Builder, "grille par nuit — garde-fous (revue Forge)" do
  let(:arrival)   { Date.today + 40 }
  let(:departure) { arrival + 2 } # 2 nuits

  def draft(**overrides)
    Reservations::Draft.new({
      arrival_date: arrival.iso8601, departure_date: departure.iso8601,
      dogs_count: 0, first_name: "Forge", last_name: "Garde",
      email: "forge-garde@example.com", phone: "+32470000000"
    }.merge(overrides))
  end

  it "F1 : une grille plus longue que la fenêtre est bornée (aucune plage après le départ)" do
    builder = described_class.new(
      draft: draft(per_night_resources: { "tente" => [2, 2, 5, 5, 5] }), # 5 valeurs, 2 nuits
      admin: true, source: "manual"
    )
    expect(builder.run).to be(true)

    campings = builder.stay.stay_items.where(bookable_type: "CampingBooking").map(&:bookable)
    expect(campings.size).to eq(1)
    expect(campings.first.to_date).to eq(departure) # jamais au-delà du départ
    expect(campings.first.people).to eq(2)
  end

  it "F4 : prix imposé + grille — les plages somment toujours à la part camping du devis" do
    builder = described_class.new(
      draft: draft(per_night_resources: { "tente" => [2, 3] }),
      admin: true, source: "manual", price_override_cents: 99_900
    )
    expect(builder.run).to be(true)

    quote = builder.stay ? Reservations::Draft.new(
      arrival_date: arrival.iso8601, departure_date: departure.iso8601, dogs_count: 0,
      first_name: "x", email: "x@x.be", per_night_resources: { "tente" => [2, 3] }
    ).quote : nil
    campings = builder.stay.stay_items.where(bookable_type: "CampingBooking").map(&:bookable)
    expect(campings.sum(&:price_cents)).to eq(quote.camping_cents)
    expect(builder.stay.reload.total_amount_cents).to eq(99_900) # l'override gouverne le total
  end
end
