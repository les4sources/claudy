require "rails_helper"

RSpec.describe Reservations::VatNumber do
  describe ".normalize" do
    it "ramène la saisie à la forme compacte de VIES" do
      expect(described_class.normalize("be 0123.456.749")).to eq("BE0123456749")
      expect(described_class.normalize("FR 12 345678901")).to eq("FR12345678901")
    end

    it "prend le pays de l'adresse quand le préfixe manque" do
      expect(described_class.normalize("0123 456 749")).to eq("BE0123456749")
      expect(described_class.normalize("123456789B01", country: "NL")).to eq("NL123456789B01")
    end

    it "complète un ancien numéro belge à 9 chiffres et écrit la Grèce EL" do
      expect(described_class.normalize("BE123456749")).to eq("BE0123456749")
      expect(described_class.normalize("GR123456789")).to eq("EL123456789")
    end

    it "rend nil pour une saisie vide" do
      expect(described_class.normalize("  ")).to be_nil
    end
  end

  describe ".valid?" do
    it "accepte un numéro belge dont la clé modulo 97 est juste" do
      expect(described_class.valid?("BE0123456749")).to be(true)
    end

    it "refuse une faute de frappe dans un numéro belge" do
      expect(described_class.valid?("BE0123456748")).to be(false)
    end

    it "contrôle le format des autres pays" do
      expect(described_class.valid?("NL123456789B01")).to be(true)
      expect(described_class.valid?("DE12345678")).to be(false)
      expect(described_class.valid?("XX123")).to be(false)
    end
  end

  it "ne demande VIES que pour l'Union européenne" do
    expect(described_class.vies_checkable?("BE0123456749")).to be(true)
    expect(described_class.vies_checkable?("CHE123456789")).to be(false)
  end
end
