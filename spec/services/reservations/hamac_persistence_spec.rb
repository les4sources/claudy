require "rails_helper"

# Issue #138 — les hamacs sont désormais PERSISTÉS (avant : devis-only, donc
# invisibles du séjour et sur-louables). Même pattern que camping/van : une
# `HamacBooking` par PLAGE CONTIGUË de valeur constante, ventilation EXACTE de la
# part hamac du devis, et invariant de total du séjour préservé.
RSpec.describe "Persistance des hamacs sur le séjour (issue #138)" do
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

  describe "Reservations::Builder — grille hamac simple [2,2,0,3]" do
    let(:grid_draft) { draft(per_night_resources: { "hamac_simple" => %w[2 2 0 3] }) }

    it "crée 2 plages aux bonnes dates/quantités, ∑ prix == quote.hamac_cents" do
      builder = Reservations::Builder.new(draft: grid_draft)
      expect(builder.run).to be(true)

      hamacs = builder.stay.stay_items.where(bookable_type: "HamacBooking")
                      .filter_map(&:bookable).sort_by(&:from_date)
      expect(hamacs.size).to eq(2)

      expect(hamacs[0].from_date).to eq(arrival)
      expect(hamacs[0].to_date).to eq(arrival + 2)
      expect(hamacs[0].kind).to eq("simple")
      expect(hamacs[0].count).to eq(2)
      expect(hamacs[0].price_cents).to eq(750 * 2 * 2)

      expect(hamacs[1].from_date).to eq(arrival + 3)
      expect(hamacs[1].to_date).to eq(arrival + 4)
      expect(hamacs[1].count).to eq(3)
      expect(hamacs[1].price_cents).to eq(750 * 3 * 1)

      expect(hamacs.sum(&:price_cents)).to eq(grid_draft.quote.hamac_cents)
    end
  end

  describe "grille MIXTE simple + double" do
    let(:mixed_draft) do
      draft(per_night_resources: { "hamac_simple" => %w[1 1 0 0], "hamac_double" => %w[0 0 2 2] })
    end

    it "ventile au prorata du TARIF de chaque type (∑ == quote.hamac_cents)" do
      builder = Reservations::Builder.new(draft: mixed_draft)
      expect(builder.run).to be(true)

      hamacs = builder.stay.stay_items.where(bookable_type: "HamacBooking")
                      .filter_map(&:bookable).index_by(&:kind)
      expect(hamacs.keys).to match_array(%w[simple double])
      expect(hamacs["simple"].price_cents).to eq(750 * 1 * 2)
      expect(hamacs["double"].price_cents).to eq(1_500 * 2 * 2)
      expect(hamacs.values.sum(&:price_cents)).to eq(mixed_draft.quote.hamac_cents)
    end
  end

  describe "invariant de total (re-ventilation, pas de double-compte)" do
    let(:full_draft) do
      draft(lodging_id: hulotte.id, per_night_resources: { "hamac_simple" => %w[1 1 1 1] })
    end

    it "laisse le total du séjour ET l'acompte strictement égaux au devis" do
      quote   = full_draft.quote
      builder = Reservations::Builder.new(draft: full_draft) # funnel public
      expect(builder.run).to be(true)
      stay = builder.stay

      expect(stay.total_amount_cents).to eq(quote.total_excluding_experiences_cents)
      expect(builder.payment.amount_cents).to eq(quote.deposit_cents)

      # Le Booking d'hébergement ne porte plus la part hamac.
      booking = stay.stay_items.where(bookable_type: "Booking").first.bookable
      expect(booking.price_cents).to eq(quote.lodging_only_cents)

      # Ventilation exhaustive : la somme des parts redonne exactement le total.
      expect(stay.bookables.sum { |b| b.try(:price_cents).to_i }).to eq(stay.total_amount_cents)
    end
  end

  describe "repli pleine-fenêtre (grille absente)" do
    it "persiste une plage couvrant tout le séjour" do
      d = draft(hamacs: [{ kind: "double", count: 1 }])
      builder = Reservations::Builder.new(draft: d)
      expect(builder.run).to be(true)

      hamac = builder.stay.stay_items.where(bookable_type: "HamacBooking").first.bookable
      expect(hamac.kind).to eq("double")
      expect(hamac.count).to eq(1)
      expect(hamac.from_date).to eq(arrival)
      expect(hamac.to_date).to eq(departure)
      expect(hamac.price_cents).to eq(d.quote.hamac_cents)
    end
  end

  describe "stock (RentalItem)" do
    before { RentalItem.create!(name: "Hamac simple", stock: 2, price_cents: 750) }

    it "refuse une demande qui dépasse le stock disponible d'une nuit" do
      HamacBooking.create!(kind: "simple", count: 2, status: "confirmed",
                           from_date: arrival + 1, to_date: arrival + 2)

      builder = Reservations::Builder.new(draft: draft(per_night_resources: { "hamac_simple" => %w[1 1 1 1] }))
      expect(builder.run).to be(false)
      expect(builder.error_message).to include("stock insuffisant")
    end

    it "accepte quand le stock suffit" do
      builder = Reservations::Builder.new(draft: draft(per_night_resources: { "hamac_simple" => %w[2 2 2 2] }))
      expect(builder.run).to be(true)
    end
  end

  describe "round-trip Stays::DraftReconstructor" do
    it "reconstruit fidèlement la grille hamacs du séjour" do
      grid = { "hamac_simple" => %w[2 2 0 3], "hamac_double" => %w[0 1 1 0] }
      builder = Reservations::Builder.new(draft: draft(per_night_resources: grid))
      expect(builder.run).to be(true)

      rebuilt = Stays::DraftReconstructor.call(builder.stay.reload)
      # Le Draft normalise la grille en chaînes (même contrat que tente/van).
      expect(rebuilt.per_night_resources["hamac_simple"]).to eq(%w[2 2 0 3])
      expect(rebuilt.per_night_resources["hamac_double"]).to eq(%w[0 1 1 0])
    end
  end

  describe "Stays::AdminUpdater" do
    let(:user) { User.create!(email: "admin-hamacs@les4sources.be", password: "password123") }

    it "reconstruit les plages à l'édition (grille modifiée)" do
      builder = Reservations::Builder.new(draft: draft(per_night_resources: { "hamac_simple" => %w[1 1 1 1] }),
                                          admin: true, status: "confirmed")
      expect(builder.run).to be(true)
      stay = builder.stay

      edited = draft(per_night_resources: { "hamac_simple" => %w[0 2 2 0] })
      updater = Stays::AdminUpdater.new(stay: stay, draft: edited, user: user)
      expect(updater.run).to be(true)

      hamacs = stay.reload.stay_items.where(bookable_type: "HamacBooking").filter_map(&:bookable)
      expect(hamacs.size).to eq(1)
      expect(hamacs.first.count).to eq(2)
      expect(hamacs.first.from_date).to eq(arrival + 1)
      expect(hamacs.first.to_date).to eq(arrival + 3)
      expect(hamacs.first.price_cents).to eq(edited.quote.hamac_cents)
    end

    it "détache les hamacs quand ils disparaissent du draft" do
      builder = Reservations::Builder.new(draft: draft(per_night_resources: { "hamac_simple" => %w[1 1 1 1] }),
                                          admin: true, status: "confirmed")
      builder.run
      stay = builder.stay

      updater = Stays::AdminUpdater.new(stay: stay, draft: draft(lodging_id: hulotte.id), user: user)
      expect(updater.run).to be(true)
      expect(stay.reload.stay_items.where(bookable_type: "HamacBooking")).to be_empty
    end

    it "ne se bloque pas lui-même sur son propre stock à la réédition" do
      RentalItem.create!(name: "Hamac simple", stock: 2, price_cents: 750)
      grid = { "hamac_simple" => %w[2 2 2 2] }
      builder = Reservations::Builder.new(draft: draft(per_night_resources: grid),
                                          admin: true, status: "confirmed")
      expect(builder.run).to be(true)

      updater = Stays::AdminUpdater.new(stay: builder.stay, draft: draft(per_night_resources: grid), user: user)
      expect(updater.run).to be(true)
    end
  end
end
