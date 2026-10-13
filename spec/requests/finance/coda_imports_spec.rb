require "rails_helper"
require Rails.root.join("spec/support/finance_builders")
require "rack/test"

RSpec.describe "Finances > Import CODA", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let!(:cash_account) do
    CashAccount.create!(name: "Triodos", kind: "bank", legal_entity: entity,
                        general_account: bank_account, iban: "BE55068000000000")
  end

  before { sign_in user }

  def uploaded(name)
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/coda/#{name}.cod"), "text/plain")
  end

  it "importe un fichier déposé et amène ses lignes à affecter" do
    expect {
      post finance_coda_imports_path, params: { file: uploaded("nominal") }
    }.to change { CashEntry.count }.by(2)

    follow_redirect!
    expect(response.body).to include("nominal.cod")

    get finance_unallocated_cash_entries_path
    expect(response.body).to include("VIREMENT GROUPE DUPONT")
  end

  # Le motif porte le relevé et l'écart chiffré : c'est ce qui permet à la compta
  # de savoir quoi demander à la banque, au lieu de « ça n'a pas marché ».
  it "affiche pourquoi un fichier est refusé, et n'en garde rien" do
    expect {
      post finance_coda_imports_path, params: { file: uploaded("ecart_intra") }
    }.not_to change { CashEntry.count }

    follow_redirect!
    expect(response.body).to include("ne correspond pas")
    expect(CodaImport.count).to eq(0)
  end

  # Le message doit dire QUEL IBAN créer : « ça n'a pas marché » oblige à
  # rouvrir le fichier à la main pour comprendre.
  it "dit quel IBAN manque quand un compte de trésorerie n'existe pas" do
    expect {
      post finance_coda_imports_path, params: { file: uploaded("multi_releves") }
    }.not_to change { CashEntry.count }

    follow_redirect!
    expect(response.body).to include("BE77068011111111").and include("Crée-le")
  end

  it "refuse un dépôt sans fichier plutôt que de planter" do
    post finance_coda_imports_path

    follow_redirect!
    expect(response.body).to include("Choisis un fichier")
  end

  it "liste les imports passés" do
    post finance_coda_imports_path, params: { file: uploaded("nominal") }

    get finance_coda_imports_path
    expect(response.body).to include("nominal.cod").and include("Importé")
  end

  # Beobank n'a pas de CODA : son export Excel passe par le même écran.
  describe "l'export Excel de Beobank" do
    let!(:beobank) do
      CashAccount.create!(name: "SRL — Beobank", kind: "bank", legal_entity: entity,
                          general_account: bank_account, iban: "BE68539007547034")
    end

    def classeur(name)
      Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/beobank/#{name}.xlsx"),
                                   "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    end

    it "importe le classeur sur le compte Beobank" do
      expect {
        post finance_coda_imports_path, params: { file: classeur("nominal") }
      }.to change { beobank.cash_entries.count }.by(5)

      follow_redirect!
      expect(response.body).to include("nominal.xlsx").and include("Export Excel 2026")
    end

    it "affiche pourquoi un classeur est refusé" do
      expect {
        post finance_coda_imports_path, params: { file: classeur("ecart") }
      }.not_to change { CashEntry.count }

      follow_redirect!
      expect(response.body).to include("ne correspond à aucun solde")
    end
  end
end
