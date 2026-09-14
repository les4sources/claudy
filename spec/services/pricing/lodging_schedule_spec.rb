require "rails_helper"

# Epic #260, phase 1 — le barème des gîtes est celui du site, et une suite de
# nuits se compose au plus juste avec ses briques.
#
# Les dates sont RÉELLES et ancrées : octobre 2026 pour la haute saison,
# janvier 2027 pour la basse. Le 5 octobre 2026 est un lundi, le 15 janvier 2027
# un vendredi — les specs le vérifient d'abord, sinon tout le reste ment.
RSpec.describe Pricing::LodgingSchedule do
  let(:lundi_5_octobre)   { Date.new(2026, 10, 5) }
  let(:vendredi_15_jan)   { Date.new(2027, 1, 15) }

  def nights(from, count) = (0...count).map { |i| from + i }

  def price(lodging, from, count)
    described_class.call(lodging, nights(from, count))
  end

  it "s'appuie sur des dates justes" do
    expect(lundi_5_octobre.wday).to eq(1)   # lundi
    expect(vendredi_15_jan.wday).to eq(5)   # vendredi
  end

  describe "les montants figés par l'epic" do
    it "La Hulotte, lundi 5 → vendredi 9 octobre 2026 : forfait 4 nuits = 1 490 €" do
      result = price("La Hulotte", lundi_5_octobre, 4)

      expect(result.total_cents).to eq(149_000)
      expect(result.segments.map(&:brick)).to eq(["package_4_nights"])
      expect(result).to be_complete
    end

    it "La Chevêche, jeudi 15 → dimanche 18 octobre : 1 nuit semaine + forfait week-end = 680 €" do
      jeudi = Date.new(2026, 10, 15)
      expect(jeudi.wday).to eq(4)

      result = price("La Chevêche", jeudi, 3)

      expect(result.total_cents).to eq(68_000)
      expect(result.segments.map(&:brick)).to eq(%w[weeknight weekend_2_nights])
    end

    it "Le Grand-Duc, nuit du vendredi 15 janvier 2027 seule : 750 € (saison basse)" do
      result = price("Le Grand-Duc", vendredi_15_jan, 1)

      expect(result.total_cents).to eq(75_000)
      expect(result.segments.map(&:brick)).to eq(["weekend_night_low_season"])
      expect(result).to be_complete
    end

    it "La Chevêche, nuit du vendredi 16 octobre 2026 seule : AUCUNE brique (haute saison)" do
      vendredi = Date.new(2026, 10, 16)
      expect(vendredi.wday).to eq(5)

      result = price("La Chevêche", vendredi, 1)

      expect(result.segments).to be_empty
      expect(result.unpriceable).to eq([vendredi])
      expect(result).not_to be_complete
    end

    it "La Chevêche, lundi 5 → dimanche 11 octobre : forfait 6 nuits = 995 €" do
      result = price("La Chevêche", lundi_5_octobre, 6)

      expect(result.total_cents).to eq(99_500)
      expect(result.segments.map(&:brick)).to eq(["package_6_nights"])
    end

    it "La Chevêche, lundi 5 → lundi 12 octobre : forfait 6 nuits + nuit du dimanche = 1 195 €" do
      result = price("La Chevêche", lundi_5_octobre, 7)

      expect(result.total_cents).to eq(119_500)
      expect(result.segments.map(&:brick)).to eq(%w[package_6_nights weeknight])
    end

    it "La Hulotte, mardi 6 → jeudi 8 octobre : 2 nuits semaine = 800 €" do
      result = price("La Hulotte", lundi_5_octobre + 1, 2)

      expect(result.total_cents).to eq(80_000)
      expect(result.segments.map(&:brick)).to eq(%w[weeknight weeknight])
    end

    it "Le Grand-Duc, vendredi 15 → dimanche 17 janvier 2027 : forfait week-end, pas 2 × 750 €" do
      result = price("Le Grand-Duc", vendredi_15_jan, 2)

      expect(result.total_cents).to eq(135_000)
      expect(result.segments.map(&:brick)).to eq(["weekend_2_nights"])
    end
  end

  # Le forfait « semaine » du Grand-Duc à 2 410 € pour 7 nuits faisait DÉCROÎTRE
  # le prix quand le séjour s'allongeait. Le nouveau barème ne le réintroduit pas.
  describe "un séjour plus long ne coûte jamais moins cher" do
    %w[La\ Chevêche La\ Hulotte Le\ Grand-Duc].each do |lodging|
      it "#{lodging} : 7 nuits coûtent plus que 4 nuits" do
        quatre = price(lodging, lundi_5_octobre, 4).total_cents
        sept   = price(lodging, lundi_5_octobre, 7).total_cents

        expect(sept).to be > quatre
      end
    end

    it "reste monotone nuit après nuit sur trois semaines" do
      totals = (1..21).map { |n| price("La Hulotte", lundi_5_octobre, n) }
                      .select(&:complete?)
                      .map(&:total_cents)

      expect(totals.each_cons(2).all? { |a, b| b >= a }).to be(true)
    end
  end

  describe "la saison basse" do
    it "s'ouvre le 15 novembre et se ferme le 14 mars" do
      expect(Pricing::LodgingSeason.low_season?(Date.new(2026, 11, 14))).to be(false)
      expect(Pricing::LodgingSeason.low_season?(Date.new(2026, 11, 15))).to be(true)
      expect(Pricing::LodgingSeason.low_season?(Date.new(2027, 3, 14))).to be(true)
      expect(Pricing::LodgingSeason.low_season?(Date.new(2027, 3, 15))).to be(false)
      expect(Pricing::LodgingSeason.low_season?(Date.new(2027, 1, 1))).to be(true)
    end
  end

  describe "la classification des nuits" do
    it "range dimanche → jeudi en semaine, vendredi et samedi en week-end" do
      semaine = (5..11).map { |d| Date.new(2026, 10, d) }.select { |d| Pricing::LodgingGrid.weeknight?(d) }

      expect(semaine.map(&:wday)).to match_array([0, 1, 2, 3, 4])
    end
  end

  it "rend un devis vide sans nuit" do
    result = described_class.call("La Hulotte", [])

    expect(result.segments).to be_empty
    expect(result).to be_complete
  end

  it "ignore la Tiny house, qui n'est pas au barème du site" do
    result = price("Tiny house", lundi_5_octobre, 2)

    expect(result.segments).to be_empty
    expect(result.unpriceable.size).to eq(2)
  end

  it "suit Paramètres > Tarifs avant la constante" do
    Rate.create!(key: "lodging.la_hulotte.weeknight", amount_cents: 42_000, label: "Hulotte — nuit semaine")
    Pricing::Rates.reset!

    expect(price("La Hulotte", lundi_5_octobre + 1, 1).total_cents).to eq(42_000)
  ensure
    Pricing::Rates.reset!
  end
end
