require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Issue #198 — un fichier CODA belge identifie le compte par sa BBAN
# (`523080601116`), claudy stocke un IBAN (`BE72 5230 8060 1116`). Sans
# rapprochement, aucun CODA belge réel n'entre, quel que soit le compte.
RSpec.describe Coda::Import, "rapprochement du compte" do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Comptes courants") }

  # On part du CODA nominal des fixtures et on n'y change QUE le numéro de
  # compte, en respectant sa géométrie : un enregistrement CODA fait exactement
  # 128 caractères, et un fichier bricolé à la main se fait refuser par le
  # parseur avant d'atteindre le rapprochement qu'on veut tester.
  NUMERO = (6..39)   # zone du numéro de compte, en base 0

  def coda_pour(numéro)
    lignes = Rails.root.join("spec/fixtures/coda/nominal.cod").read.split("\n")
    lignes.map do |ligne|
      next ligne unless ligne.start_with?("1", "8")

      ligne.dup.tap { |l| l[NUMERO] = numéro.ljust(NUMERO.size)[0, NUMERO.size] }
    end.join("\n")
  end

  def importe(numéro) = described_class.new(content: coda_pour(numéro), filename: "test.cod").run!

  context "quand le compte de trésorerie porte l'IBAN complet, avec ses espaces" do
    let!(:compte) do
      CashAccount.create!(name: "Fondation — Triodos", kind: "bank", legal_entity: entity,
                          general_account: bank_account, iban: "BE72 5230 8060 1116")
    end

    it "reconnaît la BBAN du fichier" do
      report = importe("523080601116 EUR")

      expect(report.status).to eq("imported")
      expect(CashEntry.last.cash_account).to eq(compte)
    end

    it "reconnaît aussi l'IBAN écrit en toutes lettres dans le fichier" do
      report = importe("BE72523080601116 EUR")

      expect(report.status).to eq("imported")
    end
  end

  # Le rapprochement reste strict : on ne rattache jamais « au plus proche ».
  it "refuse toujours un numéro qui ne correspond à aucun compte" do
    CashAccount.create!(name: "Fondation — Triodos", kind: "bank", legal_entity: entity,
                        general_account: bank_account, iban: "BE72 5230 8060 1116")

    expect { importe("999999999999 EUR") }
      .to raise_error(described_class::Rejected, /Aucun compte de trésorerie/)
    expect(CashEntry.count).to eq(0)
  end

  # Choisir à la place de l'humain serait pire que refuser : deux comptes qui
  # portent le même numéro, c'est une donnée à corriger, pas un arbitrage.
  it "refuse quand deux comptes portent le même numéro" do
    CashAccount.create!(name: "Fondation — Triodos", kind: "bank", legal_entity: entity,
                        general_account: bank_account, iban: "BE72 5230 8060 1116")
    CashAccount.create!(name: "Doublon saisi par erreur", kind: "bank", legal_entity: entity,
                        general_account: bank_account, iban: "523080601116")

    expect { importe("523080601116 EUR") }
      .to raise_error(described_class::Rejected, /PLUSIEURS comptes/)
    expect(CashEntry.count).to eq(0)
  end

  it "ignore les comptes sans IBAN plutôt que de les rapprocher de tout" do
    CashAccount.create!(name: "Caisse du bar", kind: "cash", legal_entity: entity,
                        general_account: build_general_account(code: "570000", name: "Caisse"))

    expect { importe("523080601116 EUR") }
      .to raise_error(described_class::Rejected, /Aucun compte de trésorerie/)
  end
end
