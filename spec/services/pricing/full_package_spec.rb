require "rails_helper"

# Epic #260, phase 3 — « la totale » : Le Grand-Duc toutes les nuits PLUS les
# deux salles et la cuisine pro tous les jours, vendu comme un forfait par nuit.
#
# Les dates sont RÉELLES et ancrées : octobre 2026 pour la haute saison, janvier
# 2027 pour la basse. Le 5 octobre 2026 est un lundi, le 15 janvier 2027 un
# vendredi — les specs le vérifient d'abord, sinon tout le reste ment.
RSpec.describe Pricing::FullPackage do
  let(:lundi_5_octobre) { Date.new(2026, 10, 5) }
  let(:vendredi_15_jan) { Date.new(2027, 1, 15) }

  def nights(from, count) = (0...count).map { |i| from + i }

  it "s'appuie sur des dates justes" do
    expect(lundi_5_octobre.wday).to eq(1)
    expect(vendredi_15_jan.wday).to eq(5)
  end

  describe "les montants figés par l'epic" do
    it "haute saison, lundi 5 → jeudi 8 octobre 2026 (3 nuits) : 3 × 1 010 = 3 030, −10 % = 2 727 €" do
      quote = described_class.quote(nights(lundi_5_octobre, 3))

      expect(quote.gross_cents).to eq(303_000)
      expect(quote.discount_percent).to eq(10)
      expect(quote.amount_cents).to eq(272_700)
    end

    it "haute saison, lundi 5 → dimanche 11 octobre 2026 (6 nuits) : 4 × 1 010 + 2 × 1 220 = 6 480, −25 % = 4 860 €" do
      quote = described_class.quote(nights(lundi_5_octobre, 6))

      expect(quote.gross_cents).to eq(648_000)
      expect(quote.discount_percent).to eq(25)
      expect(quote.amount_cents).to eq(486_000)
    end

    it "basse saison, vendredi 15 → dimanche 17 janvier 2027 (2 nuits) : 2 × 1 050 = 2 100 €" do
      quote = described_class.quote(nights(vendredi_15_jan, 2))

      expect(quote.gross_cents).to eq(210_000)
      expect(quote.discount_percent).to eq(0)
      expect(quote.amount_cents).to eq(210_000)
    end
  end

  describe "les saisons" do
    it "range le 15 mars en basse saison et le 16 mars en haute" do
      expect(described_class).to be_low_season(Date.new(2027, 3, 15))
      expect(described_class).to be_high_season(Date.new(2027, 3, 16))
    end

    it "range le 14 novembre en haute saison et le 15 novembre en basse" do
      expect(described_class).to be_high_season(Date.new(2026, 11, 14))
      expect(described_class).to be_low_season(Date.new(2026, 11, 15))
    end

    it "fait basculer les congés de Noël en haute saison" do
      expect(described_class).to be_christmas(Date.new(2026, 12, 25))
      expect(described_class).to be_high_season(Date.new(2026, 12, 25))
      # La veille du premier jour de congé reste en basse saison.
      expect(described_class).to be_low_season(Date.new(2026, 12, 18))
      # Le lendemain du dernier jour aussi.
      expect(described_class).to be_low_season(Date.new(2027, 1, 4))
    end

    it "facture une nuit de Noël au tarif haute saison" do
      # Vendredi 25 décembre 2026 : nuit de week-end, haute saison.
      expect(Date.new(2026, 12, 25).wday).to eq(5)
      expect(described_class.night_cents(Date.new(2026, 12, 25))).to eq(122_000)
    end
  end

  describe "les nuits de week-end" do
    it "compte comme week-end une nuit qui commence vendredi ou samedi" do
      expect(described_class).to be_weekend_night(Date.new(2026, 10, 9))  # vendredi
      expect(described_class).to be_weekend_night(Date.new(2026, 10, 10)) # samedi
      expect(described_class).not_to be_weekend_night(Date.new(2026, 10, 11)) # dimanche
      expect(described_class).not_to be_weekend_night(Date.new(2026, 10, 8))  # jeudi
    end
  end

  describe "les remises" do
    it "ne remise rien en dessous de 3 nuits" do
      expect(described_class.discount_percent(2)).to eq(0)
    end

    it "remise de 10 % à partir de 3 nuits" do
      expect(described_class.discount_percent(3)).to eq(10)
      expect(described_class.discount_percent(5)).to eq(10)
    end

    it "remise de 25 % à partir de 6 nuits, et au-delà" do
      expect(described_class.discount_percent(6)).to eq(25)
      expect(described_class.discount_percent(12)).to eq(25)
    end
  end

  describe "la détection" do
    def stay_days(from, nights_count) = (from..(from + nights_count)).to_a

    def occupied(days, spaces: described_class::REQUIRED_SPACES)
      spaces.to_h { |space| [space, days.to_set] }
    end

    it "s'applique quand tout est là" do
      days = stay_days(lundi_5_octobre, 3)
      expect(described_class.applies?(nights: nights(lundi_5_octobre, 3), other_lodgings: false,
                                      stay_days: days, occupied_spaces: occupied(days))).to be(true)
    end

    it "ne s'applique pas si une salle manque un seul jour" do
      days = stay_days(lundi_5_octobre, 3)
      spaces = occupied(days)
      spaces["cuisine_pro"] = (days - [days[2]]).to_set

      expect(described_class.applies?(nights: nights(lundi_5_octobre, 3), other_lodgings: false,
                                      stay_days: days, occupied_spaces: spaces)).to be(false)
    end

    it "ne s'applique pas si le Grand-Duc n'est pas pris toutes les nuits" do
      days = stay_days(lundi_5_octobre, 3)
      expect(described_class.applies?(nights: nights(lundi_5_octobre, 2), other_lodgings: false,
                                      stay_days: days, occupied_spaces: occupied(days))).to be(false)
    end

    it "ne s'applique pas si un autre gîte est de la partie" do
      days = stay_days(lundi_5_octobre, 3)
      expect(described_class.applies?(nights: nights(lundi_5_octobre, 3), other_lodgings: true,
                                      stay_days: days, occupied_spaces: occupied(days))).to be(false)
    end

    it "ne s'applique pas sur une seule nuit : deux nuits minimum" do
      days = stay_days(lundi_5_octobre, 1)
      expect(described_class.applies?(nights: nights(lundi_5_octobre, 1), other_lodgings: false,
                                      stay_days: days, occupied_spaces: occupied(days))).to be(false)
    end

    it "ne s'applique pas sans dates de séjour" do
      expect(described_class.applies?(nights: nights(lundi_5_octobre, 3), other_lodgings: false,
                                      stay_days: [], occupied_spaces: {})).to be(false)
    end
  end

  describe "le libellé" do
    it "dit le forfait, les nuits, la saison et la remise" do
      label = described_class.label(described_class.quote(nights(lundi_5_octobre, 3)))

      expect(label).to include("La totale — Le Grand-Duc + les 2 salles + cuisine pro")
      expect(label).to include("3 nuits")
      expect(label).to include("haute saison")
      expect(label).to include("−10 %")
    end

    it "ne parle pas de remise quand il n'y en a pas" do
      expect(described_class.label(described_class.quote(nights(vendredi_15_jan, 2)))).not_to include("−")
    end
  end

  describe "les tarifs" do
    it "se lisent dans Paramètres > Tarifs quand la clé y est" do
      Rate.create!(key: "full_package.high_season.weeknight", amount_cents: 90_000, unit: "cents", label: "Totale")
      Pricing::Rates.reset!

      expect(described_class.night_cents(lundi_5_octobre)).to eq(90_000)
      Pricing::Rates.reset!
    end
  end
end
