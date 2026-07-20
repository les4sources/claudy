require "rails_helper"

# Terrasse (décision Michael, 2026-07-20) — des groupes occupent UNIQUEMENT la
# terrasse (ex. randonneurs / BBQ) : forfait 2,50 €/pers/JOUR. ADMIN UNIQUEMENT,
# jamais sur le funnel public. Persistée en `CampingBooking` de `kind: "terrasse"`,
# un par JOUR d'occupation (`from = date`, `to = date + 1`).
RSpec.describe Reservations::Builder, "terrasse (ADMIN uniquement)" do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Chambre 1", level: 1)
    lodging
  end

  let(:day1) { Date.today + 30 }
  let(:day2) { Date.today + 31 }

  def draft(**overrides)
    Reservations::Draft.new({
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: "camille@example.com", phone: "+32470112233"
    }.merge(overrides))
  end

  describe "création admin — 2 lignes terrasse (jours différents)" do
    let(:d) do
      draft(
        arrival_date: day1.iso8601, departure_date: day2.iso8601,
        terrasses: [{ date: day1.iso8601, people: 8 }, { date: day2.iso8601, people: 5 }]
      )
    end

    it "crée 2 CampingBooking kind terrasse, un par jour, prix people×250" do
      builder = described_class.new(draft: d, admin: true, source: "manual")
      expect(builder.run).to be(true)

      terrasses = builder.stay.stay_items.map(&:bookable)
                         .select { |b| b.is_a?(CampingBooking) && b.kind == "terrasse" }
                         .sort_by(&:from_date)
      expect(terrasses.size).to eq(2)

      first, second = terrasses
      expect(first.people).to eq(8)
      expect(first.from_date).to eq(day1)
      expect(first.to_date).to eq(day1 + 1)          # occupation d'UN jour
      expect(first.price_cents).to eq(2_000)         # 8 × 2,50 €
      expect(second.people).to eq(5)
      expect(second.from_date).to eq(day2)
      expect(second.price_cents).to eq(1_250)        # 5 × 2,50 €

      # Total du séjour juste = somme des terrasses (aucun autre réservable).
      expect(builder.stay.total_amount_cents).to eq(3_250)
      # Aucun paiement (canal admin).
      expect(builder.stay.payments).to be_empty
    end

    it "n'assimile PAS la terrasse au camping (kind tente)" do
      described_class.new(draft: d, admin: true, source: "manual").run
      expect(CampingBooking.where(kind: "tente")).to be_empty
      expect(CampingBooking.where(kind: "terrasse").count).to eq(2)
    end
  end

  describe "combinée à un hébergement — invariant de ventilation" do
    it "Booking(hébergement pur) + terrasses == total, sans double-compte" do
      d = draft(
        lodging_id: hulotte.id,
        arrival_date: day1.iso8601, departure_date: (day1 + 2).iso8601, # 2 nuits Hulotte
        terrasses: [{ date: day1.iso8601, people: 4 }]
      )
      builder = described_class.new(draft: d, admin: true, source: "manual")
      expect(builder.run).to be(true)

      terrace_cents = CampingBooking.where(kind: "terrasse").sum(:price_cents)
      expect(terrace_cents).to eq(1_000)              # 4 × 2,50 €
      # Hébergement PUR = 2 nuits Hulotte (48 500 + 26 000), SANS la terrasse.
      expect(builder.booking.price_cents).to eq(74_500)
      expect(builder.booking.price_cents + terrace_cents).to eq(builder.stay.total_amount_cents)
    end
  end

  describe "funnel public — anti-critère (param terrasses forgé)" do
    it "IGNORE terrasses hors admin, même en param forgé" do
      d = draft(
        lodging_id: hulotte.id,
        arrival_date: day1.iso8601, departure_date: (day1 + 2).iso8601,
        terrasses: [{ date: day1.iso8601, people: 8 }] # param forgé
      )
      builder = described_class.new(draft: d) # PAS admin (funnel public)
      expect(builder.run).to be(true)

      expect(CampingBooking.where(kind: "terrasse")).to be_empty
      # Total inchangé = 2 nuits Hulotte, la terrasse forgée n'est jamais facturée.
      expect(builder.stay.total_amount_cents).to eq(74_500)
      expect(builder.booking.price_cents).to eq(74_500)
    end
  end
end

RSpec.describe PricingModel, "terrasse" do
  def draft(**attrs)
    OpenStruct.new({ lodging: nil, nights: 0, dogs_count: 0,
                     campings: [], vans: [], halls: [], meals: [], terrasses: [] }.merge(attrs))
  end

  it "produit une ligne :terrace par entrée (people × 2,50 €)" do
    quote = described_class.quote(draft(terrasses: [{ date: "2026-08-12", people: 8 },
                                                    { date: "2026-08-13", people: 5 }]))
    expect(quote.terrace_cents).to eq(3_250)
    expect(quote.total_cents).to eq(3_250)
    expect(quote.breakdown.map { |l| l[:label] }).to all(match(/Terrasse/))
  end

  it "exclut la terrasse de l'hébergement pur (lodging_only_cents)" do
    grand_duc = Lodging.create!(name: "Le Grand-Duc", price_night_cents: 75_000)
    quote = described_class.quote(draft(lodging: grand_duc, nights: 1,
                                        terrasses: [{ date: "2026-08-12", people: 4 }]))
    expect(quote.terrace_cents).to eq(1_000)
    expect(quote.lodging_only_cents).to eq(75_000) # 1 nuit Grand-Duc, hors terrasse
    expect(quote.lodging_only_cents + quote.terrace_cents).to eq(quote.total_excluding_experiences_cents)
  end
end
