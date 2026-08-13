require "rails_helper"

# Le prix sourcier se calcule depuis le prix d'achat et une MARGE par canal,
# paramétrable globalement (Michael, 2026-08-13). Une seule notion, trois
# valeurs — bar, cellier, repas.
RSpec.describe Catalog::BuildPrice do
  def seed_margin(channel, percent, active_from: Date.new(2023, 1, 1), active_until: nil)
    rate = Rate.find_or_create_by!(key: described_class.margin_key(channel)) do |r|
      r.amount_cents = percent
      r.unit = "percent"
    end
    rate.rate_versions.create!(amount_cents: percent, active_from: active_from, active_until: active_until)
    rate
  end

  describe "marge par canal" do
    it "applique la marge du bar au prix d'achat" do
      seed_margin("bar", 10)

      expect(described_class.new(channel: "bar", purchase_price_cents: 191).member_price_cents).to eq(210)
    end

    it "applique une marge différente au cellier" do
      seed_margin("grocery", 17)

      expect(described_class.new(channel: "grocery", purchase_price_cents: 240).member_price_cents).to eq(281)
    end

    it "accepte une marge nulle sur les repas" do
      seed_margin("meal", 0)

      expect(described_class.new(channel: "meal", purchase_price_cents: 500).member_price_cents).to eq(500)
    end

    # La preuve que la marge est bien un paramètre : la changer change le prix,
    # sans toucher une ligne de Ruby.
    it "suit la marge paramétrée" do
      seed_margin("bar", 30)

      expect(described_class.new(channel: "bar", purchase_price_cents: 100).member_price_cents).to eq(130)
    end

    it "retombe sur la marge documentée quand la clé n'est pas paramétrée" do
      expect(described_class.new(channel: "bar", purchase_price_cents: 100).member_price_cents).to eq(110)
    end

    it "arrondit au cent" do
      seed_margin("bar", 10)

      expect(described_class.new(channel: "bar", purchase_price_cents: 105).member_price_cents).to eq(116)
    end
  end

  # Reconstituer un palier de 2024 doit utiliser la marge de 2024.
  it "lit la marge à la date du palier" do
    seed_margin("bar", 10, active_until: Date.new(2025, 12, 31))
    Rate.find_by(key: described_class.margin_key("bar"))
        .rate_versions.create!(amount_cents: 20, active_from: Date.new(2026, 1, 1))

    ancien = described_class.new(channel: "bar", purchase_price_cents: 100, on: Date.new(2024, 6, 1))
    actuel = described_class.new(channel: "bar", purchase_price_cents: 100, on: Date.new(2026, 6, 1))

    expect(ancien.member_price_cents).to eq(110)
    expect(actuel.member_price_cents).to eq(120)
  end

  it "ne devine rien sans prix d'achat" do
    seed_margin("bar", 10)

    expect(described_class.new(channel: "bar").member_price_cents).to be_nil
  end

  describe "prix public" do
    # Le public n'est pas une marge : au bar c'est une décision commerciale
    # (4,00 € pour une bière achetée 1,91 €), on ne le fixe jamais d'office.
    it "n'est pas proposé au bar" do
      seed_margin("bar", 10)

      expect(described_class.new(channel: "bar", purchase_price_cents: 191).run!.public_price_cents).to be_nil
    end

    it "se propose au cellier depuis le prix de référence" do
      Rate.create!(key: "grocery.public_ratio", amount_cents: 105, unit: "percent")
          .rate_versions.create!(amount_cents: 105, active_from: Date.new(2023, 1, 1))

      proposal = described_class.new(channel: "grocery", purchase_price_cents: 240,
                                     reference_price_cents: 295).run!

      expect(proposal.public_price_cents).to eq(310)
    end

    it "ne propose rien au cellier sans prix de référence" do
      expect(described_class.new(channel: "grocery", purchase_price_cents: 240).run!.public_price_cents).to be_nil
    end
  end
end
