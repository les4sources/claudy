require "rails_helper"

# Les deux règles de prix vont en SENS OPPOSÉ, et c'est tout l'enjeu de ces
# specs : au bar le prix sourcier se calcule sur l'achat majoré et reste très en
# dessous du public ; au cellier il se calcule sur une référence minorée. Une
# inversion des deux passerait inaperçue à l'œil — pas ici.
RSpec.describe Catalog::BuildPrice do
  # Les coefficients vivent dans `rates`, en unité `percent` (110 = 1,10).
  def seed_rate(key, percent, active_from: Date.new(2023, 1, 1), active_until: nil)
    rate = Rate.create!(key: key, amount_cents: percent, unit: "percent")
    rate.rate_versions.create!(amount_cents: percent, active_from: active_from, active_until: active_until)
    rate
  end

  describe "bar" do
    before { seed_rate("bar.member_markup", 110) }

    # Le cas réel du tableau : Moinette achetée 1,91 €, sourcier 2,10 €,
    # public 4,00 €. Le sourcier paie donc BIEN MOINS que le public.
    it "propose le prix d'achat majoré de 10 % pour le sourcier" do
      proposal = described_class.new(channel: "bar", purchase_price_cents: 191).run!

      expect(proposal.member_price_cents).to eq(210)
    end

    # Le prix public d'une bière est une décision commerciale, pas un multiple
    # de l'achat : le proposer serait suggérer un chiffre faux.
    it "ne propose aucun prix public" do
      proposal = described_class.new(channel: "bar", purchase_price_cents: 191).run!

      expect(proposal.public_price_cents).to be_nil
    end

    it "arrondit au cent" do
      proposal = described_class.new(channel: "bar", purchase_price_cents: 105).run!

      expect(proposal.member_price_cents).to eq(116) # 115,5 → 116
    end
  end

  describe "cellier" do
    before do
      seed_rate("grocery.member_ratio", 95)
      seed_rate("grocery.public_ratio", 105)
    end

    # Cas réel : avoine de référence 2,95 € → sourcier 2,80 €, public 3,10 €.
    it "propose 95 % de la référence pour le sourcier et 105 % pour le public" do
      proposal = described_class.new(channel: "grocery", reference_price_cents: 295).run!

      expect(proposal.member_price_cents).to eq(280)
      expect(proposal.public_price_cents).to eq(310)
    end

    it "place le prix sourcier EN DESSOUS du prix public" do
      proposal = described_class.new(channel: "grocery", reference_price_cents: 295).run!

      expect(proposal.member_price_cents).to be < proposal.public_price_cents
    end
  end

  # La preuve que le coefficient n'est pas codé en dur : le changer change la
  # proposition, sans toucher une ligne de Ruby.
  it "suit le coefficient paramétré dans les tarifs" do
    seed_rate("bar.member_markup", 130)

    proposal = described_class.new(channel: "bar", purchase_price_cents: 100).run!

    expect(proposal.member_price_cents).to eq(130)
  end

  # Proposer un palier daté doit utiliser la majoration DE CETTE DATE, sinon
  # rejouer 2024 appliquerait les coefficients de 2026.
  it "lit le coefficient à la date du palier" do
    seed_rate("bar.member_markup", 110, active_from: Date.new(2023, 1, 1), active_until: Date.new(2025, 12, 31))
    rate = Rate.find_by(key: "bar.member_markup")
    rate.rate_versions.create!(amount_cents: 120, active_from: Date.new(2026, 1, 1))

    ancien = described_class.new(channel: "bar", purchase_price_cents: 100, on: Date.new(2024, 6, 1)).run!
    actuel = described_class.new(channel: "bar", purchase_price_cents: 100, on: Date.new(2026, 6, 1)).run!

    expect(ancien.member_price_cents).to eq(110)
    expect(actuel.member_price_cents).to eq(120)
  end

  it "retombe sur la constante documentée quand la clé n'est pas paramétrée" do
    proposal = described_class.new(channel: "bar", purchase_price_cents: 100).run!

    expect(proposal.member_price_cents).to eq(110)
  end

  it "ne propose rien sans prix de départ" do
    proposal = described_class.new(channel: "bar").run!

    expect(proposal.member_price_cents).to be_nil
  end

  it "ne propose rien sur un canal sans règle" do
    proposal = described_class.new(channel: "meal", purchase_price_cents: 500).run!

    expect(proposal.member_price_cents).to be_nil
  end
end
