require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Ce qui compte ici n'est pas qu'un import réussisse — c'est qu'un import qui
# ne devrait pas passer ne laisse RIEN derrière lui, et qu'un fichier redéposé
# ne double rien.
RSpec.describe Coda::Import do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let!(:cash_account) do
    CashAccount.create!(name: "Triodos", kind: "bank", legal_entity: entity,
                        general_account: bank_account, iban: "BE55068000000000")
  end

  def fixture(name) = Rails.root.join("spec/fixtures/coda/#{name}.cod").read
  def import(name) = described_class.new(content: fixture(name), filename: "#{name}.cod").run!

  describe "un fichier nominal" do
    it "crée une ligne de trésorerie par mouvement, en attente d'affectation" do
      expect { import("nominal") }.to change { CashEntry.count }.by(2)

      entries = CashEntry.order(:entry_date)
      expect(entries.map(&:amount_cents)).to eq([130_000, -45_000])
      expect(entries.map(&:status).uniq).to eq(["pending"])
      expect(entries.first.communication).to include("VIREMENT GROUPE DUPONT")
    end

    it "n'invente aucune affectation" do
      import("nominal")

      expect(CashAllocation.count).to eq(0)
    end

    it "garde le fichier et son relevé" do
      report = import("nominal")

      expect(report.status).to eq("imported")
      expect(CodaImport.last.status).to eq("imported")
      expect(CodaStatement.last.sequence_number).to eq("001")
      expect(CodaStatement.last.new_balance_cents).to eq(185_000)
    end
  end

  describe "l'idempotence" do
    it "refuse de rejouer le même fichier — niveau sha256" do
      import("nominal")

      expect { @report = import("nominal") }.not_to change { CashEntry.count }
      expect(@report.status).to eq("already_imported")
    end

    # Le cas courant : les banques renvoient volontiers des fichiers qui se
    # chevauchent. Le relevé, pas seulement le fichier, doit être idempotent.
    it "ignore un relevé déjà importé arrivé dans un autre fichier" do
      import("nominal")
      autre = fixture("nominal").sub("TESTFILE01", "TESTFILE02")

      report = described_class.new(content: autre, filename: "bis.cod").run!

      expect(report.entries_created).to eq(0)
      expect(report.statements_skipped).to eq(1)
      expect(CashEntry.count).to eq(2)
    end
  end

  describe "les contrôles bloquants" do
    it "refuse un relevé qui ne se referme pas sur lui-même, sans rien créer" do
      expect {
        expect { import("ecart_intra") }.to raise_error(described_class::Rejected, /ne correspond pas/)
      }.not_to change { CashEntry.count }

      expect(CodaImport.count).to eq(0)
    end

    it "refuse une rupture de chaînage entre deux relevés du fichier" do
      expect {
        expect { import("rupture_chainage") }.to raise_error(described_class::Rejected, /manque/)
      }.not_to change { CashEntry.count }
    end

    # Le trou entre deux imports : celui qu'aucun contrôle intra-fichier ne voit.
    it "refuse un fichier dont l'ancien solde ne suit pas le dernier relevé importé" do
      import("nominal")

      expect { import("trou_continuite") }.to raise_error(described_class::Rejected, /manque/)
      expect(CashEntry.count).to eq(2)
    end

    # Un débit et un crédit fabriqués qui se compensent satisfont les trois
    # autres contrôles : seul le total du fichier les attrape.
    it "refuse un fichier dont les totaux de fin ne collent pas aux mouvements lus" do
      lignes = fixture("nominal").lines
      index = lignes.index { |l| l.start_with?("9") }
      fin = lignes[index].dup
      fin[22, 15] = "000000099999000"
      lignes[index] = fin

      expect {
        expect {
          described_class.new(content: lignes.join, filename: "faux_total.cod").run!
        }.to raise_error(described_class::Rejected, /Total des débits/)
      }.not_to change { CashEntry.count }
    end

    it "refuse un IBAN qu'aucun compte de trésorerie ne porte" do
      cash_account.update!(iban: "BE99999999999999")

      expect {
        import("nominal")
      }.to raise_error(described_class::Rejected, /Crée-le/)
    end
  end

  describe "plusieurs comptes" do
    let!(:second_account) do
      CashAccount.create!(name: "Triodos épargne", kind: "bank", legal_entity: entity,
                          general_account: bank_account, iban: "BE77068011111111")
    end

    it "répartit les lignes sur le bon compte" do
      import("multi_releves")

      expect(cash_account.cash_entries.count).to eq(1)
      expect(second_account.cash_entries.count).to eq(1)
      expect(second_account.cash_entries.first.amount_cents).to eq(-7_550)
    end
  end
end
