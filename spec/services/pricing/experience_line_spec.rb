require "rails_helper"

RSpec.describe Pricing::ExperienceLine do
  # Petite fabrique en ligne (pas de FactoryBot dans ce repo). `name` est
  # requis + unique côté Experience ; on le rend distinct par cas.
  def experience(fixed_cents: 0, per_cents: nil, name: "Atelier #{SecureRandom.hex(4)}")
    Experience.create!(name: name, fixed_price_cents: fixed_cents, price_cents: per_cents)
  end

  describe ".amount_cents" do
    it "additionne le forfait fixe et le prix par personne × participants" do
      exp = experience(fixed_cents: 5_000, per_cents: 1_500)
      expect(described_class.amount_cents(exp, participants: 3)).to eq(5_000 + 1_500 * 3) # 9 500
    end

    it "facture le seul forfait fixe quand il n'y a pas de prix par personne" do
      exp = experience(fixed_cents: 4_000, per_cents: nil)
      expect(described_class.amount_cents(exp, participants: 5)).to eq(4_000)
    end

    it "facture le seul prix par personne quand il n'y a pas de forfait fixe" do
      exp = experience(fixed_cents: 0, per_cents: 1_500)
      expect(described_class.amount_cents(exp, participants: 4)).to eq(6_000)
    end

    it "renvoie 0 pour une activité gratuite" do
      exp = experience(fixed_cents: 0, per_cents: nil)
      expect(described_class.amount_cents(exp, participants: 2)).to eq(0)
    end
  end

  describe ".rate_label — les 4 variantes du barème" do
    it "forfait fixe + prix par personne" do
      exp = experience(fixed_cents: 4_000, per_cents: 1_500)
      expect(described_class.rate_label(exp)).to eq("40 € + 15 €/pers")
    end

    it "prix par personne seul" do
      exp = experience(fixed_cents: 0, per_cents: 1_500)
      expect(described_class.rate_label(exp)).to eq("15 €/pers")
    end

    it "forfait fixe seul" do
      exp = experience(fixed_cents: 4_000, per_cents: nil)
      expect(described_class.rate_label(exp)).to eq("40 €")
    end

    it "gratuit quand ni forfait ni prix par personne" do
      exp = experience(fixed_cents: 0, per_cents: nil)
      expect(described_class.rate_label(exp)).to eq("Gratuit")
    end
  end
end
