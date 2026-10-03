require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #359, phase 4 — une règle par carnet et par artisan actif. Des règles qui
# PROPOSENT : le service ne crée ni affectation ni suggestion.
RSpec.describe Shop::SeedAllocationRules do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:cellier) { build_general_account(code: "701002", name: "Cellier", klass: 7, nature: "revenue") }
  let!(:boulangerie) { build_general_account(code: "701003", name: "Boulangerie", klass: 7, nature: "revenue") }
  let!(:artisanat) { build_general_account(code: "701005", name: "Artisanat (dépôt-vente)", klass: 7, nature: "revenue") }
  let!(:emilie) { Consignor.create!(name: "Émilie Dupont", settlement_mode: "invoice") }
  let!(:bruno) { Consignor.create!(name: "Bruno", settlement_mode: "invoice") }

  def rule_for(keyword) = AllocationRule.find_by(communication_contains: keyword)

  it "crée EPICERIE, PAIN et une règle par artisan actif, entrantes, à 90 % de confiance" do
    Consignor.create!(name: "Ancien", settlement_mode: "invoice", active: false)

    result = described_class.new.run

    expect(result.created.size).to eq(4)
    expect(rule_for("EPICERIE").general_account).to eq(cellier)
    expect(rule_for("PAIN").general_account).to eq(boulangerie)
    expect(rule_for("ARTISANAT EMILIE").general_account).to eq(artisanat)
    expect(rule_for("ARTISANAT BRUNO").general_account).to eq(artisanat)
    expect(rule_for("ARTISANAT ANCIEN")).to be_nil
    expect(AllocationRule.pluck(:direction, :confidence).uniq).to eq([["incoming", 90]])
    expect(AllocationRule.pluck(:legal_entity_id).uniq).to eq([entity.id])
    expect(AllocationSuggestion.count + CashAllocation.count).to eq(0)
  end

  it "est idempotente : une seconde passe ne crée rien" do
    described_class.new.run

    second = nil
    expect { second = described_class.new.run }.not_to(change { AllocationRule.count })
    expect(second.created).to be_empty
    expect(second.kept.size).to eq(4)
  end

  it "ne retouche pas une règle existante pointée ailleurs, et le signale" do
    bar = build_general_account(code: "700300", name: "Bar et cellier", klass: 7, nature: "revenue")
    AllocationRule.create!(label: "Épicerie maison", communication_contains: "epicerie",
                           general_account: bar, legal_entity: entity)

    result = described_class.new.run

    expect(AllocationRule.where("LOWER(communication_contains) = 'epicerie'").count).to eq(1)
    expect(rule_for("epicerie").general_account).to eq(bar)
    expect(result.warnings.join).to include("Épicerie maison", "laissée telle quelle")
  end

  it "suit la correspondance choisie dans les réglages" do
    autre = build_general_account(code: "701009", name: "Pains spéciaux", klass: 7, nature: "revenue")
    settings = ShopSetting.current
    settings.update!(bread_account: autre)

    described_class.new(settings: settings).run

    expect(rule_for("PAIN").general_account).to eq(autre)
  end

  it "sans compte de produit : pas de règle, un avertissement" do
    boulangerie.update!(active: false)

    result = described_class.new.run

    expect(rule_for("PAIN")).to be_nil
    expect(result.warnings.join).to include("Boulangerie", "701003", "pas de règle « PAIN »")
  end

  it "signale deux artisans au même prénom" do
    Consignor.create!(name: "Emilie Martin", settlement_mode: "invoice")

    result = described_class.new.run

    expect(AllocationRule.where(communication_contains: "ARTISANAT EMILIE").count).to eq(1)
    expect(result.warnings.join).to include("partagent le mot-clé « ARTISANAT EMILIE »")
  end

  describe "#for_consignor" do
    it "crée la règle d'un seul artisan" do
      expect { described_class.new.for_consignor(emilie) }.to change { AllocationRule.count }.by(1)
      expect(rule_for("ARTISANAT EMILIE")).to be_present
    end

    it "ignore un artisan inactif" do
      emilie.update!(active: false)

      expect { described_class.new.for_consignor(emilie) }.not_to(change { AllocationRule.count })
    end
  end
end
