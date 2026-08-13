require "rails_helper"

# Issue #158 — écrans Finances > Fiches papier.
RSpec.describe "Finances > Fiches papier", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "compta@les4sources.be", password: "password123") }
  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let!(:ada) { MemberAccount.create!(kind: "household", household: household, name: "Ada") }
  let!(:moinette) do
    item = CatalogItem.create!(name: "Moinette", channel: "bar", unit: "piece")
    item.catalog_prices.create!(active_from: Date.new(2023, 1, 1), member_price_cents: 210)
    item
  end
  let(:sheet) { PaperSheet.create!(period_month: Date.new(2026, 8, 1), channel: "bar") }

  before { sign_in user }

  describe "GET /finance/paper_sheets/:id/encode" do
    it "rend une ligne par article du canal et une colonne par compte actif" do
      get encode_finance_paper_sheet_path(sheet)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Moinette")
      expect(response.body).to include("cells[#{ada.id}][#{moinette.id}]")
    end

    it "n'affiche pas les articles d'un autre canal" do
      CatalogItem.create!(name: "Avoine", channel: "grocery", unit: "kg")

      get encode_finance_paper_sheet_path(sheet)

      expect(response.body).not_to include("Avoine")
    end

    # La matrice desktop et l'accordéon mobile rendent DEUX champs par cellule,
    # avec le même `name` — côté Rails, c'est le dernier qui gagne. Le contrôleur
    # Stimulus désactive la mise en page inactive avant de soumettre, en se
    # fiant à `data-layout`. Un champ non étiqueté échapperait à ce filtre et
    # écraserait silencieusement la saisie : ce test garde l'étiquetage.
    it "étiquette chaque cellule par sa mise en page" do
      get encode_finance_paper_sheet_path(sheet)

      cellules = response.body.scan(/data-encoding-matrix-target="cell"[^>]*/)
      expect(cellules).to be_present
      expect(cellules.count { |c| c.include?('data-layout="desktop"') }).to eq(1)
      expect(cellules.count { |c| c.include?('data-layout="mobile"') }).to eq(1)
      expect(cellules.all? { |c| c.include?("data-layout=") }).to be(true)
    end

    it "annonce clairement l'absence de catalogue plutôt que d'afficher une grille vide" do
      vide = PaperSheet.create!(period_month: Date.new(2026, 8, 1), channel: "meal")

      get encode_finance_paper_sheet_path(vide)

      expect(response.body).to include("Aucun article actif")
    end
  end

  describe "POST save_encoding" do
    it "crée les écritures de la matrice" do
      expect {
        post save_encoding_finance_paper_sheet_path(sheet), params: {
          entry_mode: "quantity", cells: { ada.id.to_s => { moinette.id.to_s => "3" } }
        }
      }.to change(AccountEntry, :count).by(1)

      expect(AccountEntry.last.amount_cents).to eq(630)
      expect(AccountEntry.last.paper_sheet_id).to eq(sheet.id)
    end

    it "réenregistrer ne duplique rien" do
      post save_encoding_finance_paper_sheet_path(sheet), params: {
        entry_mode: "quantity", cells: { ada.id.to_s => { moinette.id.to_s => "3" } }
      }

      expect {
        post save_encoding_finance_paper_sheet_path(sheet), params: {
          entry_mode: "quantity", cells: { ada.id.to_s => { moinette.id.to_s => "4" } }
        }
      }.not_to change(AccountEntry, :count)

      expect(AccountEntry.last.amount_cents).to eq(840)
    end

    it "remonte le récapitulatif dans le message" do
      post save_encoding_finance_paper_sheet_path(sheet), params: {
        entry_mode: "quantity", cells: { ada.id.to_s => { moinette.id.to_s => "3" } }
      }

      follow_redirect!
      expect(response.body).to include("1 créée(s)")
    end
  end

  describe "CRUD" do
    it "crée une fiche et redirige vers son encodage" do
      post finance_paper_sheets_path, params: {
        paper_sheet: { period_month: "2026-08-15", channel: "bar", entry_mode: "quantity" }
      }

      # N'importe quel jour du mois se cale sur le 1er.
      expect(PaperSheet.last.period_month).to eq(Date.new(2026, 8, 1))
      expect(response).to redirect_to(encode_finance_paper_sheet_path(PaperSheet.last))
    end
  end

  describe "sans authentification" do
    it "redirige vers la connexion" do
      sign_out user

      get finance_paper_sheets_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
