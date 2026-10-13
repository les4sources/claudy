require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Les classeurs de `spec/fixtures/beobank` imitent l'export « Vos comptes » de
# Beobank : une feuille de synthèse, une feuille par compte (IBAN fictif
# BE68 5390 0754 7034), une feuille masquée, le solde initial en formule sans
# valeur, et la colonne Solde dans l'ordre déroutant de Beobank (le solde de
# fin de journée sur la première ligne du jour).
#
# - nominal : 5 mouvements du 01/09 au 08/09/2026, dont deux identiques le
#   même jour ; solde 0 → 170,17 €.
# - ecart : le même, avec un solde affiché faux le 03/09.
# - suite : l'export suivant, qui recouvre le 08/09 et ajoute deux lignes du
#   06/10 ; solde final 160,34 €.
# - trou : seulement les deux lignes du 06/10.
RSpec.describe Beobank::Import do
  include FinanceBuilders

  let(:entity) { build_legal_entity(name: "SRL de test", form: "srl") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550100", name: "Beobank") }
  let!(:cash_account) do
    CashAccount.create!(name: "SRL — Beobank", kind: "bank", legal_entity: entity,
                        general_account: bank_account, iban: "BE68 5390 0754 7034")
  end

  def fixture(name) = Rails.root.join("spec/fixtures/beobank/#{name}.xlsx").binread
  def import(name) = described_class.new(content: fixture(name), filename: "#{name}.xlsx").run!

  describe "un export nominal" do
    it "crée une ligne de trésorerie par mouvement, en attente d'affectation" do
      report = import("nominal")

      expect(report.status).to eq("imported")
      expect(report.entries_created).to eq(5)
      entries = CashEntry.order(:entry_date, :id)
      expect(entries.map(&:amount_cents)).to eq([-500, 88_000, -483, -35_000, -35_000])
      expect(entries.first.value_date).to eq(Date.new(2026, 8, 31))
      expect(entries.first.communication).to eq("Forfait mensuel (TVA incl.)")
      expect(entries.map(&:status).uniq).to eq(["pending"])
      expect(CashAllocation.count).to eq(0)
    end

    it "garde les deux mouvements identiques du même jour" do
      import("nominal")

      expect(CashEntry.where(amount_cents: -35_000).count).to eq(2)
      expect(CashEntry.where(amount_cents: -35_000).pluck(:fingerprint).uniq.size).to eq(2)
    end

    it "garde le fichier et son solde dans l'historique des imports" do
      import("nominal")

      statement = CodaStatement.last
      expect(statement.cash_account).to eq(cash_account)
      expect(statement.old_balance_cents).to eq(0)
      expect(statement.new_balance_cents).to eq(17_017)
      expect(statement.new_balance_date).to eq(Date.new(2026, 10, 13))
      expect(statement.label).to eq("Export Excel 2026")
      expect(CodaImport.last.file_reference).to eq("Beobank (Excel)")
    end
  end

  describe "les contrôles" do
    it "refuse un export dont un solde affiché ne suit pas les montants, et n'en garde rien" do
      expect {
        expect { import("ecart") }.to raise_error(Beobank::ParseError, %r{03/09/2026})
      }.not_to change { [CashEntry.count, CodaImport.count] }
    end

    it "refuse un IBAN qu'aucun compte de trésorerie ne porte" do
      cash_account.update!(iban: "BE72523080601116")

      expect { import("nominal") }.to raise_error(described_class::Rejected, /BE68539007547034/)
    end

    it "refuse un export qui laisse un trou après la dernière ligne connue" do
      import("nominal")

      expect {
        expect { import("trou") }.to raise_error(described_class::Rejected, /entre-deux/)
      }.not_to change { CashEntry.count }
    end

    it "refuse un classeur qui n'est pas un export Beobank" do
      expect {
        described_class.new(content: "pas un classeur", filename: "x.xlsx").run!
      }.to raise_error(Beobank::ParseError, /classeur Excel/)
    end
  end

  describe "les exports qui se recouvrent" do
    it "n'importe que la part nouvelle de l'export suivant" do
      import("nominal")

      report = import("suite")

      expect(report.entries_created).to eq(2)
      expect(report.entries_skipped).to eq(3)
      expect(CashEntry.count).to eq(7)
      expect(CashEntry.sum(:amount_cents)).to eq(16_034)
    end

    it "refuse de rejouer le même fichier" do
      import("nominal")

      report = import("nominal")

      expect(report.status).to eq("already_imported")
      expect(CashEntry.count).to eq(5)
    end

    # Les lignes Beobank déjà en prod sont entrées par l'API, sans empreinte :
    # c'est sur leurs colonnes que l'empreinte se recalcule.
    it "reconnaît les lignes déjà entrées sans empreinte" do
      import("nominal")
      CashEntry.find_each do |entry|
        entry.update_columns(fingerprint: nil, external_ref: "api-reprise-#{entry.id}", value_date: nil)
      end

      expect(import("suite").entries_created).to eq(2)
      expect(CashEntry.count).to eq(7)
    end

    # Michael a saisi à la main les deux lignes du 06/10 en attendant l'import.
    it "reconnaît une ligne saisie à la main par sa date et son montant" do
      import("nominal")
      CashEntry.create!(cash_account: cash_account, entry_date: Date.new(2026, 10, 6), amount_cents: -483,
                        label: "Okioki")
      CashEntry.create!(cash_account: cash_account, entry_date: Date.new(2026, 10, 6), amount_cents: -500,
                        label: "Frais Beobank")

      report = import("suite")

      expect(report.entries_created).to eq(0)
      expect(report.to_text).to include("2 reconnue(s) par leur date et leur montant")
      expect(CashEntry.count).to eq(7)
    end

    it "refuse quand une ligne du journal ne correspond à aucun mouvement du fichier" do
      import("nominal")
      CashEntry.create!(cash_account: cash_account, entry_date: Date.new(2026, 10, 6), amount_cents: -1_234,
                        label: "Saisie erronée")

      expect {
        expect { import("suite") }.to raise_error(described_class::Rejected, /ne correspond à aucun/)
      }.not_to change { CashEntry.count }
    end
  end
end
