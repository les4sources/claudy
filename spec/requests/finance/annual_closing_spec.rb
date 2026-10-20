require "rails_helper"
require "zip"
require Rails.root.join("spec/support/finance_builders")

# Clôture d'exercice, comptes annuels au schéma BNB, immobilisations et export
# pour le comptable (revue expert-comptable du 2026-10-20).
RSpec.describe "Finances > Clôture et états annuels", type: :request do
  include FinanceBuilders

  let(:user) { User.create!(email: "compta-cloture@les4sources.be", password: "password123") }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:year_2025) { build_fiscal_year(entity, year: 2025) }
  let!(:bank) { build_general_account(code: "550000", name: "Banque", klass: 5, nature: "asset") }
  let!(:sales) { build_general_account(code: "700000", name: "Ventes", klass: 7, nature: "revenue") }
  let!(:rent) { build_general_account(code: "613000", name: "Loyers", klass: 6, nature: "expense") }
  let!(:furniture) { build_general_account(code: "240000", name: "Mobilier", klass: 2) }
  let!(:depreciation) { build_general_account(code: "240001", name: "Amortissements mobilier", klass: 2) }
  let!(:dotation) { build_general_account(code: "630100", name: "Dotations aux amortissements", klass: 6, nature: "expense") }

  before do
    sign_in user
    post_simple_entry(entity: entity, debit_account: bank, credit_account: sales, amount_cents: 500_000, entry_date: Date.new(2025, 3, 1))
    post_simple_entry(entity: entity, debit_account: rent, credit_account: bank, amount_cents: 200_000, entry_date: Date.new(2025, 4, 1))
  end

  def body = CGI.unescapeHTML(response.body)

  describe "la clôture" do
    it "montre l'aperçu : résultat, affectation et à-nouveau" do
      get closing_finance_fiscal_year_path(year_2025)

      expect(response).to have_http_status(:ok)
      expect(body).to include("Clôturer l'exercice 2025", "693000", "140000", "À-nouveau 2026, par compte", "550000")
    end

    it "clôture, pose l'à-nouveau, puis rouvre avec un motif" do
      post close_finance_fiscal_year_path(year_2025), params: { opening: "generate" }

      expect(response).to redirect_to(finance_fiscal_years_path)
      expect(year_2025.reload).to be_closed
      year_2026 = entity.fiscal_years.reload.find { |year| year.starts_on.year == 2026 }
      expect(Accounting::Balances.opening?(year_2026)).to be(true)

      follow_redirect!
      expect(body).to include("clôturé", "Rouvrir")

      post reopen_finance_fiscal_year_path(year_2025), params: { reason: "Correction d'une facture oubliée" }
      expect(response).to redirect_to(finance_fiscal_years_path)
      expect(year_2025.reload).not_to be_closed
      expect(Accounting::Balances.opening?(year_2026)).to be(false)
    end

    it "refuse de rouvrir sans motif" do
      Accounting::CloseFiscalYear.new(fiscal_year: year_2025, opening: "none").run!

      post reopen_finance_fiscal_year_path(year_2025), params: { reason: "" }
      expect(year_2025.reload).to be_closed
      expect(flash[:alert]).to be_present
    end

    it "ne clôture plus par le formulaire de l'exercice" do
      patch finance_fiscal_year_path(year_2025), params: { fiscal_year: { status: "closed" } }
      expect(year_2025.reload).not_to be_closed
    end
  end

  describe "les comptes annuels" do
    it "affiche le bilan et le compte de résultats au schéma BNB" do
      get finance_annual_accounts_path(fiscal_year_id: year_2025.id)

      expect(response).to have_http_status(:ok)
      expect(body).to include("Actif", "Passif", "Compte de résultats", "54/58", "9904")
    end

    it "s'exporte en CSV, rubrique par rubrique" do
      get finance_annual_accounts_path(fiscal_year_id: year_2025.id, format: :csv)

      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("Code BNB", "Total de l'actif", "3000,00")
    end
  end

  describe "les immobilisations" do
    let(:asset_params) do
      { legal_entity_id: entity.id, name: "Poêle de masse", general_account_id: furniture.id,
        depreciation_account_id: depreciation.id, expense_account_id: dotation.id, acquired_on: "2025-09-15",
        acquisition: "1 200", useful_life_years: 5, prior_depreciation: "" }
    end

    it "inscrit un bien, passe sa dotation puis l'annule" do
      post finance_fixed_assets_path, params: { fixed_asset: asset_params }
      asset = FixedAsset.last
      expect(asset).to have_attributes(acquisition_cents: 120_000, prior_depreciation_cents: 0)

      get finance_fixed_assets_path(legal_entity_id: entity.id, fiscal_year_id: year_2025.id)
      expect(body).to include("Poêle de masse", "Passer les dotations 2025", "à passer : 80 €")

      post depreciate_finance_fixed_assets_path, params: { fiscal_year_id: year_2025.id }
      expect(asset.reload.depreciations.sum(:amount_cents)).to eq(8_000)

      delete finance_fixed_asset_path(asset)
      expect(FixedAsset.exists?(asset.id)).to be(true)

      post finance_cancel_fixed_asset_depreciation_path(asset.depreciations.first)
      expect(asset.reload.depreciations).to be_empty
    end

    it "refuse un bien sans valeur" do
      post finance_fixed_assets_path, params: { fixed_asset: asset_params.merge(acquisition: "") }

      expect(response).to have_http_status(:unprocessable_content)
      expect(FixedAsset.count).to eq(0)
    end

    it "corrige un bien" do
      asset = FixedAsset.create!(asset_params.except(:acquisition, :prior_depreciation).merge(acquisition_cents: 120_000))

      get edit_finance_fixed_asset_path(asset)
      expect(response).to have_http_status(:ok)

      patch finance_fixed_asset_path(asset), params: { fixed_asset: { useful_life_years: 10 } }
      expect(asset.reload.useful_life_years).to eq(10)
    end
  end

  describe "l'export pour le comptable" do
    it "livre un ZIP de CSV" do
      get finance_accountant_export_path(fiscal_year_id: year_2025.id)
      expect(response).to have_http_status(:ok)

      get finance_download_accountant_export_path(fiscal_year_id: year_2025.id)
      expect(response.media_type).to eq("application/zip")

      names = []
      Zip::InputStream.open(StringIO.new(response.body)) do |zip|
        while (entry = zip.get_next_entry)
          names << entry.name
          expect(zip.read).to include("5000,00") if entry.name == "journaux.csv"
        end
      end
      expect(names).to contain_exactly("LISEZMOI.txt", "journaux.csv", "grand-livre.csv", "balance.csv",
                                       "balance-tiers.csv", "comptes-annuels.csv", "immobilisations.csv")
    end
  end
end
