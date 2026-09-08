require "rails_helper"

# Epic #248, phase 1 — l'artisan déposant et son contrat.
RSpec.describe Consignor do
  def build_consignor(**attrs)
    described_class.new({ name: "Eline", settlement_mode: "invoice" }.merge(attrs))
  end

  describe "la commission" do
    it "vaut 20 % par défaut" do
      expect(described_class.new.commission_percent).to eq(20)
    end

    it "accepte 0 et 100" do
      expect(build_consignor(commission_percent: 0)).to be_valid
      expect(build_consignor(commission_percent: 100)).to be_valid
    end

    it "refuse au-delà de 100 et en dessous de 0" do
      expect(build_consignor(commission_percent: 101)).not_to be_valid
      expect(build_consignor(commission_percent: -1)).not_to be_valid
    end
  end

  describe "le mode de règlement" do
    it "refuse un mode inconnu" do
      expect(build_consignor(settlement_mode: "cash")).not_to be_valid
    end

    it "exige un IBAN en mode virement" do
      consignor = build_consignor(settlement_mode: "transfer", iban: nil)

      expect(consignor).not_to be_valid
      expect(consignor.errors[:iban].join).to include("virement")
    end

    it "n'exige pas d'IBAN quand l'artisan facture" do
      expect(build_consignor(settlement_mode: "invoice", iban: nil)).to be_valid
    end
  end

  describe "l'IBAN" do
    it "accepte un IBAN belge valide et le normalise" do
      consignor = build_consignor(settlement_mode: "transfer", iban: "be68 5390 0754 7034")

      expect(consignor).to be_valid
      expect(consignor.iban).to eq("BE68539007547034")
    end

    it "refuse un IBAN dont la clé de contrôle est fausse" do
      expect(build_consignor(settlement_mode: "transfer", iban: "BE68539007547035")).not_to be_valid
    end

    it "refuse un IBAN de la bonne clé mais de la mauvaise longueur pour son pays" do
      expect(build_consignor(settlement_mode: "transfer", iban: "BE6853900754703")).not_to be_valid
    end

    it "est chiffré en base : la colonne ne contient pas l'IBAN en clair" do
      consignor = described_class.create!(name: "Eline", settlement_mode: "transfer",
                                          iban: "BE68539007547034")

      stored = described_class.connection.select_value(
        "SELECT iban FROM consignors WHERE id = #{consignor.id}"
      )
      expect(stored).not_to include("BE68539007547034")
      expect(consignor.reload.iban).to eq("BE68539007547034")
    end

    it "masque tout sauf les quatre derniers caractères pour l'affichage" do
      expect(build_consignor(iban: "BE68539007547034").iban_masked).to eq("•••• 7034")
    end
  end

  describe "les dates de contrat" do
    it "refuse une fin antérieure au début" do
      consignor = build_consignor(starts_on: Date.new(2026, 9, 1), ends_on: Date.new(2026, 8, 1))

      expect(consignor).not_to be_valid
      expect(consignor.errors[:ends_on]).to be_present
    end

    it "dit si le contrat court à une date donnée" do
      consignor = build_consignor(starts_on: Date.new(2026, 9, 1), ends_on: Date.new(2026, 12, 31))

      expect(consignor).to be_running_on(Date.new(2026, 10, 1))
      expect(consignor).not_to be_running_on(Date.new(2026, 8, 31))
      expect(consignor).not_to be_running_on(Date.new(2027, 1, 1))
    end

    it "ne court pas quand le contrat est désactivé" do
      expect(build_consignor(active: false)).not_to be_running_on(Date.current)
    end
  end

  describe "le lien facultatif vers un membre de l'équipe" do
    let!(:human) { Human.create!(name: "Eline Dupont", email: "eline@les4sources.be") }

    it "hérite du nom et de l'email quand ils ne sont pas saisis" do
      consignor = described_class.create!(human: human, settlement_mode: "invoice")

      expect(consignor.name).to eq("Eline Dupont")
      expect(consignor.email).to eq("eline@les4sources.be")
    end

    it "n'écrase jamais une saisie explicite" do
      consignor = described_class.create!(human: human, name: "Atelier Eline",
                                          email: "atelier@example.com", settlement_mode: "invoice")

      expect(consignor.name).to eq("Atelier Eline")
      expect(consignor.email).to eq("atelier@example.com")
    end
  end

  it "trie les actifs d'abord, puis par nom" do
    described_class.create!(name: "Zoé", settlement_mode: "invoice")
    described_class.create!(name: "Amine", settlement_mode: "invoice", active: false)
    described_class.create!(name: "Bruno", settlement_mode: "invoice")

    expect(described_class.ordered.map(&:name)).to eq(%w[Bruno Zoé Amine])
  end
end
