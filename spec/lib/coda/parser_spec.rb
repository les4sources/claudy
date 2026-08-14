require "rails_helper"
require Rails.root.join("lib/coda/parser")

# Les fixtures sont construites par `spec/fixtures/coda/README_generator.rb`, qui
# place chaque champ à sa position en la retypant depuis `docs/coda-layout.md` —
# indépendamment du parseur, pour que les deux ne partagent pas la même erreur de
# décalage. C'est tout l'intérêt : un parseur testé par son propre placeur de
# champs ne teste rien.
RSpec.describe Coda::Parser do
  def fixture(name) = Rails.root.join("spec/fixtures/coda/#{name}.cod").read

  describe "un fichier nominal" do
    let(:file) { described_class.call(fixture("nominal")) }
    let(:statement) { file.statements.first }

    it "lit l'en-tête" do
      expect(file.creation_date).to eq(Date.new(2026, 8, 15))
      expect(file.file_reference).to eq("TESTFILE01")
      expect(file.addressee).to eq("LES 4 SOURCES")
    end

    it "lit le compte, ses soldes et ses dates" do
      expect(statement.account_number).to eq("BE55068000000000")
      expect(statement.currency).to eq("EUR")
      expect(statement.old_balance_cents).to eq(100_000)
      expect(statement.old_balance_date).to eq(Date.new(2026, 7, 31))
      expect(statement.new_balance_cents).to eq(185_000)
      expect(statement.sequence_number).to eq("001")
    end

    # Le signe est du point de vue du titulaire : crédit = l'argent entre.
    it "lit les mouvements avec leur signe" do
      expect(statement.movements.size).to eq(2)
      expect(statement.movements.map(&:amount_cents)).to eq([130_000, -45_000])
      expect(statement.movements.first.value_date).to eq(Date.new(2026, 8, 12))
      expect(statement.movements.first.entry_date).to eq(Date.new(2026, 8, 12))
      expect(statement.movements.first.transaction_code).to eq("01500000")
    end

    it "colle l'enregistrement d'information à la communication du mouvement" do
      expect(statement.movements.first.communication)
        .to include("VIREMENT GROUPE DUPONT").and include("PAIEMENT SEJOUR 12 AU 15 AOUT")
    end

    it "referme le relevé sur lui-même" do
      expect(statement.movements_total_cents).to eq(statement.balance_delta_cents)
    end

    it "lit les totaux de l'enregistrement de fin" do
      expect(file.debit_total_cents).to eq(45_000)
      expect(file.credit_total_cents).to eq(130_000)
      expect(file.records_count).to eq(4)
    end
  end

  describe "une communication structurée et une contrepartie" do
    let(:statement) { described_class.call(fixture("structuree")).statements.first }
    let(:movement) { statement.movements.first }

    it "garde le type de communication structurée avec sa valeur" do
      expect(movement).to be_structured
      expect(movement.communication).to start_with("101 123456789012345")
    end

    it "lit la contrepartie apportée par les enregistrements 2.2 et 2.3" do
      expect(movement.counterparty_account).to eq("BE62510007547061")
      expect(movement.counterparty_name).to eq("ASSOCIATION DUPONT")
      expect(movement.counterparty_bic).to eq("GEBABEBB")
      expect(movement.customer_reference).to eq("REFCLIENT99")
      expect(movement.communication).to include("SUITE COMMUNICATION")
    end
  end

  describe "plusieurs relevés" do
    let(:file) { described_class.call(fixture("multi_releves")) }

    it "découpe un relevé par couple ancien solde / nouveau solde" do
      expect(file.statements.size).to eq(2)
      expect(file.statements.map(&:account_number)).to eq(%w[BE55068000000000 BE77068011111111])
      expect(file.statements.last.movements.first.amount_cents).to eq(-7_550)
    end
  end

  describe "les refus" do
    it "refuse une ligne qui n'a pas 128 caractères" do
      expect {
        described_class.call("0000015082600005" + "\n")
      }.to raise_error(Coda::ParseError, /caractères au lieu de 128/)
    end

    it "refuse un type d'enregistrement inconnu" do
      ligne = "7" + (" " * 127)
      expect { described_class.call(ligne) }.to raise_error(Coda::ParseError, /type/)
    end

    it "refuse un fichier sans enregistrement de fin" do
      sans_fin = fixture("nominal").lines[0..-2].join
      expect { described_class.call(sans_fin) }.to raise_error(Coda::ParseError, /fin/)
    end

    it "refuse un relevé sans nouveau solde" do
      tronque = fixture("nominal").lines.reject { |l| l.start_with?("8") }.join
      expect { described_class.call(tronque) }.to raise_error(Coda::ParseError, /nouveau solde/)
    end

    # Le refus plutôt que l'arrondi : on n'invente pas un centime sur de
    # l'argent réel, et un arrondi silencieux se découvre six mois plus tard.
    it "refuse un montant dont la troisième décimale n'est pas nulle" do
      lignes = fixture("nominal").lines
      mouvement = lignes.find { |l| l.start_with?("21") }.dup
      mouvement[32, 15] = "000000000130001"
      lignes[lignes.index { |l| l.start_with?("21") }] = mouvement

      expect { described_class.call(lignes.join) }.to raise_error(Coda::ParseError, /troisième décimale/)
    end

    it "refuse un fichier qui en concatène deux" do
      double = fixture("nominal") + fixture("multi_releves")

      expect { described_class.call(double) }.to raise_error(Coda::ParseError, /séparément/)
    end

    # `to_i` transformerait « ABCD » en 0 — et 0, c'est le détail du mouvement
    # principal : une donnée douteuse serait importée comme une vraie ligne.
    it "refuse un numéro de séquence qui n'est pas numérique" do
      lignes = fixture("nominal").lines
      index = lignes.index { |l| l.start_with?("21") }
      mouvement = lignes[index].dup
      mouvement[2, 4] = "ABCD"
      lignes[index] = mouvement

      expect { described_class.call(lignes.join) }.to raise_error(Coda::ParseError, /séquence illisible/i)
    end

    it "refuse un signe inconnu" do
      lignes = fixture("nominal").lines
      index = lignes.index { |l| l.start_with?("21") }
      mouvement = lignes[index].dup
      mouvement[31] = "7"
      lignes[index] = mouvement

      expect { described_class.call(lignes.join) }.to raise_error(Coda::ParseError, /Signe/)
    end
  end
end
