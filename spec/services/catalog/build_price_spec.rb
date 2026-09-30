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

  # Le prix public reste une décision humaine : le service ne fait que le
  # conseiller, à 30 % de marge sur le prix d'achat (Michael, 2026-09-30).
  describe "prix public conseillé" do
    it "applique 30 % de marge au prix d'achat, sur tous les canaux" do
      expect(described_class.new(channel: "grocery", purchase_price_cents: 200).run!.recommended_public_price_cents).to eq(260)
      expect(described_class.new(channel: "bar", purchase_price_cents: 183).run!.recommended_public_price_cents).to eq(238)
    end

    it "ne conseille rien sans prix d'achat" do
      expect(described_class.new(channel: "grocery").run!.recommended_public_price_cents).to be_nil
    end
  end
end
