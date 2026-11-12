require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# La photo de la feuille papier de caisse (Michael, 2026-11-12) : une par mois,
# pour référence, remplaçable.
RSpec.describe "Comptabilité > Caisse — la photo de la feuille papier", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let(:user) { User.create!(email: "caisse-photo@les4sources.be", password: "password123") }
  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:caisse_compte) { build_general_account(code: "570000", name: "Caisse") }
  let!(:caisse) { build_cash_account(entity, caisse_compte, name: "Caisse du domaine", kind: "cash") }

  let(:photo) { fixture_file_upload("fiche.png", "image/png") }
  let(:pdf) { fixture_file_upload("ticket.pdf", "application/pdf") }

  before { sign_in user }

  def upload(file, month: "2026-06")
    post finance_cash_sheet_photo_path(month: month, cash_account_id: caisse.id), params: { photo: file }
  end

  it "propose de joindre la photo, dans un formulaire multipart" do
    get finance_cash_sheet_path(month: "2026-06")

    page = Nokogiri::HTML(response.body)
    form = page.at_css("#cash-sheet-photo form:has(input[type=file][name=photo])")
    expect(form).to be_present
    # Sans `multipart`, Turbo jetterait le fichier sans rien dire.
    expect(form["enctype"]).to eq("multipart/form-data")
    expect(response.body).to include("Joindre la photo")
  end

  it "joint la photo au mois et l'affiche sur la feuille" do
    expect { upload(photo) }.to change(CashSheetPhoto, :count).by(1)

    sheet_photo = CashSheetPhoto.for(caisse, Date.new(2026, 6, 1))
    expect(sheet_photo.file.filename.to_s).to eq("fiche.png")
    expect(sheet_photo.uploaded_by).to eq(user)

    get finance_cash_sheet_path(month: "2026-06")
    expect(response.body).to include("fiche.png", "Remplacer", "Retirer")
    expect(Nokogiri::HTML(response.body).at_css("#cash-sheet-photo img")).to be_present

    # Le mois voisin n'a pas de photo.
    get finance_cash_sheet_path(month: "2026-07")
    expect(response.body).not_to include("fiche.png")
  end

  it "remplace la photo du mois au lieu d'en ajouter une seconde" do
    upload(photo)

    expect { upload(pdf) }.not_to change(CashSheetPhoto, :count)
    expect(CashSheetPhoto.for(caisse, Date.new(2026, 6, 1)).file.filename.to_s).to eq("ticket.pdf")
  end

  it "se joint aussi à un mois arrêté : elle ne passe aucune écriture" do
    allow(MonthClosing).to receive(:closed?).and_return(true)

    expect { upload(photo) }.to change(CashSheetPhoto, :count).by(1)
  end

  it "refuse un fichier qui n'est ni une photo ni un PDF" do
    texte = fixture_file_upload("unifi_devices.json", "application/json")

    expect { upload(texte) }.not_to change(CashSheetPhoto, :count)
    follow_redirect!
    expect(response.body).to include("photo (JPEG, PNG, HEIC…) ou un PDF")
  end

  it "retire la photo du mois" do
    upload(photo)

    expect do
      delete finance_cash_sheet_photo_path(month: "2026-06", cash_account_id: caisse.id)
    end.to change(CashSheetPhoto, :count).by(-1)
  end

  it "redessine la feuille en flux Turbo" do
    post finance_cash_sheet_photo_path(month: "2026-06", cash_account_id: caisse.id),
         params: { photo: photo }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("fiche.png")
  end
end
