require "rails_helper"

# Epic #359, phase 3 — l'artisan imprime SA feuille depuis son espace, et règle
# lui-même la photo et la phrase qui y figurent.
RSpec.describe "Portail — la feuille de l'artisan (epic #359, phase 3)", type: :request do
  include ActiveJob::TestHelper

  let!(:settings) { ShopSetting.create!(iban: "BE68539007547034", beneficiary_name: "Fondation Les 4 Sources") }
  let!(:eline) do
    Consignor.create!(name: "Eline Martin", settlement_mode: "invoice", email: "eline@example.com", portal_enabled: true)
  end
  let!(:bruno) do
    Consignor.create!(name: "Bruno", settlement_mode: "invoice", email: "bruno@example.com", portal_enabled: true,
                      tagline: "Bols en grès")
  end

  def sign_in_consignor(email)
    perform_enqueued_jobs { post portal_code_path, params: { email: email, context: "consignor" } }
    code = ActionMailer::Base.deliveries.last.body.encoded[/\b\d{6}\b/]
    post portal_login_path, params: { email: email, code: code }
  end

  before { ActionMailer::Base.deliveries.clear }

  it "sans session artisan, renvoie vers la porte de l'artisan" do
    get portal_consignor_sheet_path
    expect(response).to redirect_to(portal_path(context: "consignor"))
    get portal_consignor_profile_path
    expect(response).to redirect_to(portal_path(context: "consignor"))
  end

  context "Eline connectée" do
    before { sign_in_consignor("eline@example.com") }

    it "le tableau de bord mène à la feuille et au profil" do
      get portal_consignments_path
      expect(response.body).to include(portal_consignor_sheet_path, portal_consignor_profile_path)
      expect(response.body).not_to include("bientôt disponible")
    end

    it "imprime SA feuille, jamais celle d'un autre" do
      get portal_consignor_sheet_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ARTISANAT ELINE", "Feuille n° 1")
      expect(response.body).not_to include("Bruno", "Bols en grès")
      expect(eline.reload.sheets_printed_count).to eq(1)
      expect(bruno.reload.sheets_printed_count).to eq(0)
    end

    it "règle sa photo et sa phrase, qui apparaissent sur la feuille" do
      photo = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/capture.png"), "image/png")

      patch portal_consignor_profile_path, params: { consignor: { tagline: "Céramiques du Bocq", portrait: photo } }
      expect(response).to redirect_to(portal_consignments_path)
      expect(eline.reload.tagline).to eq("Céramiques du Bocq")
      expect(eline.portrait).to be_attached

      get portal_consignor_sheet_path
      expect(response.body).to include("Céramiques du Bocq")
      expect(Nokogiri::HTML(response.body).at_css("[data-sheet='consignor'] img")).to be_present
    end

    it "refuse autre chose qu'une photo" do
      text = Rack::Test::UploadedFile.new(StringIO.new("pas une image"), "text/plain", original_filename: "notes.txt")
      patch portal_consignor_profile_path, params: { consignor: { portrait: text } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(eline.reload.portrait).not_to be_attached
    end
  end
end
