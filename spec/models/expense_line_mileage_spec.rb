require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #241, phase 2 — une note de MISSION se remplit en kilomètres.
#
# Le montant n'est jamais tapé : c'est km × indemnité DU JOUR de la ligne, et
# l'indemnité se fige sur la ligne. Le barème belge change chaque année ; une
# note de mars doit rester payée au barème de mars, même relue en décembre.
RSpec.describe ExpenseLine, "kilomètres" do
  include FinanceBuilders

  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:travel) { build_general_account(code: GeneralAccount::TRAVEL_CODE, name: "Déplacements", klass: 6, nature: "expense") }
  let(:human) { Human.create!(name: "Sébastien Test") }

  def mission(kind: "mileage")
    ExpenseReport.create!(kind: kind, human: human, legal_entity: entity, submitted_on: Date.new(2026, 6, 1))
  end

  def ligne(report, **attrs)
    report.expense_lines.create!({ spent_on: Date.new(2026, 5, 28), label: "Yvoir → Gembloux",
                                   general_account: travel }.merge(attrs))
  end

  describe "le calcul" do
    it "dérive le montant des kilomètres et du barème du jour" do
      line = ligne(mission, distance_km: 84)

      expect(line.rate_cents_per_km).to eq(Pricing::Catalog::MILEAGE_PER_KM_CENTS)
      # 84 km × 0,47 € = 39,48 €.
      expect(line.amount_cents).to eq(3_948)
    end

    it "accepte une distance décimale" do
      line = ligne(mission, distance_km: 12.5)

      expect(line.amount_cents).to eq((12.5 * 47).round)
    end

    it "lit et écrit les kilomètres avec une virgule décimale" do
      line = ExpenseLine.new
      line.distance_in_km = "12,5"

      expect(line.distance_km).to eq(12.5)
      expect(line.distance_in_km).to eq("12,5")
    end

    it "refuse une ligne de mission sans kilomètres, et le dit en kilomètres" do
      line = mission.expense_lines.new(spent_on: Date.new(2026, 5, 28), label: "Trajet",
                                       general_account: travel)

      expect(line).not_to be_valid
      expect(line.errors[:distance_km]).to be_present
    end

    it "refuse une distance nulle ou négative" do
      line = mission.expense_lines.new(spent_on: Date.new(2026, 5, 28), label: "Trajet",
                                       general_account: travel, distance_km: 0)

      expect(line).not_to be_valid
    end
  end

  describe "le barème daté" do
    it "applique le barème EN VIGUEUR au jour de la ligne" do
      rate = Rate.create!(key: Pricing::Catalog::MILEAGE_PER_KM_KEY, amount_cents: 47,
                          unit: "cents", label: "Indemnité kilométrique")
      rate.rate_versions.create!(amount_cents: 42, active_from: Date.new(2026, 1, 1),
                                 active_until: Date.new(2026, 5, 31))
      rate.rate_versions.create!(amount_cents: 47, active_from: Date.new(2026, 6, 1))
      Pricing::Rates.reset!

      avant = ligne(mission, distance_km: 100, spent_on: Date.new(2026, 5, 15))
      apres = ligne(mission, distance_km: 100, spent_on: Date.new(2026, 6, 15))

      expect(avant.rate_cents_per_km).to eq(42)
      expect(avant.amount_cents).to eq(4_200)
      expect(apres.rate_cents_per_km).to eq(47)
      expect(apres.amount_cents).to eq(4_700)
    end

    it "ne réécrit PAS le taux d'une ligne déjà enregistrée quand le barème change" do
      line = ligne(mission, distance_km: 100)
      expect(line.rate_cents_per_km).to eq(47)

      rate = Rate.create!(key: Pricing::Catalog::MILEAGE_PER_KM_KEY, amount_cents: 55,
                          unit: "cents", label: "Indemnité kilométrique")
      Pricing::Rates.reset!

      # On touche un champ sans rapport : le taux figé doit tenir.
      line.update!(supplier_name: "CRA-W")

      expect(line.reload.rate_cents_per_km).to eq(47)
      expect(line.amount_cents).to eq(4_700)
      expect(rate).to be_persisted
    end

    it "va rechercher le barème quand la DATE de la ligne change" do
      rate = Rate.create!(key: Pricing::Catalog::MILEAGE_PER_KM_KEY, amount_cents: 47,
                          unit: "cents", label: "Indemnité kilométrique")
      rate.rate_versions.create!(amount_cents: 42, active_from: Date.new(2026, 1, 1),
                                 active_until: Date.new(2026, 5, 31))
      rate.rate_versions.create!(amount_cents: 47, active_from: Date.new(2026, 6, 1))
      Pricing::Rates.reset!

      line = ligne(mission, distance_km: 100, spent_on: Date.new(2026, 6, 15))
      expect(line.rate_cents_per_km).to eq(47)

      line.update!(spent_on: Date.new(2026, 5, 15))

      expect(line.reload.rate_cents_per_km).to eq(42)
      expect(line.amount_cents).to eq(4_200)
    end
  end

  it "laisse les notes de FRAIS ordinaires intouchées" do
    report = mission(kind: "expenses")
    line = ligne(report, amount_cents: 2_490, distance_km: nil)

    expect(line.amount_cents).to eq(2_490)
    expect(line.rate_cents_per_km).to be_nil
  end

  it "totalise la note depuis ses lignes kilométriques" do
    report = mission
    ligne(report, distance_km: 84)
    ligne(report, distance_km: 40, label: "Yvoir → Namur")

    expect(report.reload.total_cents).to eq((84 + 40) * 47)
  end
end
