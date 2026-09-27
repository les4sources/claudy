require "rails_helper"

# Epic #359, phase 3 — les feuilles imprimables des carnets de l'épicerie et le
# réglage de leurs QR. Des pages A4 HTML, jamais de PDF.
RSpec.describe "Carnets de l'épicerie — feuilles imprimables (epic #359, phase 3)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-carnets@les4sources.be", password: "password123") }
  let!(:settings) do
    ShopSetting.create!(iban: "BE68539007547034", bic: "GKCCBEBB", beneficiary_name: "Fondation Les 4 Sources")
  end
  let!(:emilie) do
    Consignor.create!(name: "Émilie Dupont", settlement_mode: "invoice", tagline: "Savons au lait d'ânesse")
  end

  def html = Nokogiri::HTML(response.body)

  def grocery_item(name, category:, public_cents:, member_cents:, active: true, channel: "grocery")
    item = CatalogItem.create!(name: name, channel: channel, unit: "kg", category: category, active: active)
    item.catalog_prices.create!(active_from: Date.current - 10, public_price_cents: public_cents, member_price_cents: member_cents)
    item
  end

  it "exige une session Devise" do
    [shop_grocery_sheet_path, shop_bread_sheet_path, shop_grocery_prices_sheet_path, shop_settings_path,
     sheet_consignor_path(emilie)].each do |path|
      get path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  context "connecté" do
    before { sign_in user }

    it "la feuille Épicerie : QR EPICERIE, six blocs client, numérotée et datée" do
      get shop_grocery_sheet_path
      expect(response).to have_http_status(:ok)
      expect(html.at_css("[data-sheet='grocery'] svg.epc-qr")).to be_present
      expect(response.body).to include("Scannez, entrez votre total, la communication est déjà remplie", "EPICERIE",
                                       "BE68 5390 0754 7034", "Feuille n° 1",
                                       "Imprimée le #{Date.current.strftime('%d/%m/%Y')}")
      blocks = html.css("[data-sheet-block]")
      expect(blocks.size).to eq(6)
      expect(blocks.first.css("tbody tr").size).to eq(7) # 5 lignes, le total, « payé par »
      expect(blocks.first.text).to include("TOTAL", "QR", "Virement", "Caisse")

      get shop_grocery_sheet_path
      expect(response.body).to include("Feuille n° 2")
    end

    it "la feuille Boulangerie : l'avertissement en haut, QR PAIN" do
      get shop_bread_sheet_path
      warning = html.at_css("[data-sheet-bread-warning]")
      expect(warning.text).to include("déjà payé", "ne le notez pas ici", "surplus")
      expect(response.body.index("data-sheet-bread-warning")).to be < response.body.index("epc-qr")
      expect(response.body).to include("PAIN", "Feuille n° 1")
    end

    it "sans coordonnées bancaires : pas de QR, un encadré, et le compteur n'avance pas" do
      settings.update!(iban: nil)
      get shop_grocery_sheet_path
      expect(html.at_css("svg.epc-qr")).to be_nil
      expect(html.at_css("[data-sheet-qr-missing]")).to be_present
      expect(response.body).not_to include("Feuille n°")
      expect(settings.reload.grocery_sheets_printed_count).to eq(0)
    end

    it "la feuille de prix : articles du cellier actifs, par catégorie, au prix public du jour" do
      grocery_item("Riz complet", category: "Vrac", public_cents: 480, member_cents: 390)
      grocery_item("Pâtes", category: "Vrac", public_cents: 350, member_cents: 290)
      grocery_item("Muesli", category: "Petit-déjeuner", public_cents: 900, member_cents: 750)
      grocery_item("Ancien article", category: "Vrac", public_cents: 100, member_cents: 100, active: false)
      grocery_item("Bière", category: "Vrac", public_cents: 300, member_cents: 250, channel: "bar")

      get shop_grocery_prices_sheet_path
      categories = html.css("[data-sheet-category]").map { |c| c["data-sheet-category"] }
      expect(categories).to eq(["Petit-déjeuner", "Vrac"])
      vrac = html.at_css("[data-sheet-category='Vrac']").text
      expect(vrac).to include("Pâtes", "Riz complet", "4,80", "/ kg")
      expect(vrac).not_to include("3,90", "Ancien article", "Bière")
      expect(html.at_css("[data-sheet-prices-date]").text).to include("Prix au #{Date.current.strftime('%d/%m/%Y')}")
    end

    it "la variante habitant affiche le prix habitant" do
      grocery_item("Riz complet", category: "Vrac", public_cents: 480, member_cents: 390)
      get shop_grocery_prices_sheet_path(audience: "member")
      expect(html.at_css("[data-sheet='grocery_prices']")["data-audience"]).to eq("member")
      expect(response.body).to include("Prix habitant", "3,90")
      expect(response.body).not_to include("4,80")
    end

    it "la feuille d'un artisan depuis l'admin : prénom, phrase, QR à son mot-clé, 25 lignes vides, aucun prix" do
      item = CatalogItem.create!(name: "Savon lavande", channel: "craft", unit: "piece", consignor: emilie)
      item.catalog_prices.create!(active_from: Date.current - 5, public_price_cents: 650, member_price_cents: 650)

      get sheet_consignor_path(emilie)
      expect(response).to have_http_status(:ok)
      sheet = html.at_css("[data-sheet='consignor']")
      expect(sheet.at_css("h1").text).to eq("Émilie")
      expect(sheet.text).to include("Savons au lait d'ânesse", "ARTISANAT EMILIE", "Feuille n° 1")
      expect(sheet.css("tbody tr").size).to eq(25)
      expect(sheet.text).not_to include("Savon lavande", "6,50")
      expect(emilie.reload.sheets_printed_count).to eq(1)
    end

    it "le réglage des coordonnées bancaires" do
      get shop_settings_path
      expect(response.body).to include("Bénéficiaire", "BE68 5390 0754 7034")

      patch shop_settings_path, params: { shop_setting: { iban: "BE71 0961 2345 6769", bic: "GKCCBEBB", beneficiary_name: "Fondation" } }
      expect(response).to redirect_to(shop_settings_path)
      expect(settings.reload.iban).to eq("BE71096123456769")

      patch shop_settings_path, params: { shop_setting: { iban: "BE00 0000" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "la liste des artisans mène aux feuilles" do
      get consignors_path
      expect(response.body).to include(sheet_consignor_path(emilie), shop_grocery_sheet_path, shop_bread_sheet_path,
                                       shop_grocery_prices_sheet_path, shop_settings_path)
    end
  end
end
