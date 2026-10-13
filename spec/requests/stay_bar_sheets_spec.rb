require "rails_helper"

# Feuille de bar d'un groupe (Michael, 2026-10-13) : l'écran d'encodage, la
# photo jointe et le bloc « Bar » de la fiche séjour.
RSpec.describe "Fiche séjour — feuille de bar", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-bar@les4sources.be", password: "password123") }
  let(:customer) do
    Customer.create!(email: "scouts@example.com", customer_type: "organization", organization_name: "Scouts de Namur")
  end
  let(:stay) do
    Stay.create!(customer: customer, status: "confirmed",
                 arrival_date: Date.new(2026, 10, 8), departure_date: Date.new(2026, 10, 11))
  end
  let!(:biere) do
    CatalogItem.create!(name: "Moinette", channel: "bar", category: "Bières").tap do |item|
      item.catalog_prices.create!(active_from: Date.new(2026, 1, 1), member_price_cents: 250, public_price_cents: 350)
    end
  end

  before { sign_in user }

  it "liste les articles du bar au prix public" do
    get stay_bar_sheet_path(stay)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Moinette")
    expect(response.body).to include("Bières")
    expect(response.body).to include("Enregistrer la feuille")
  end

  it "enregistre la feuille et l'ajoute au total du séjour" do
    patch stay_bar_sheet_path(stay), params: { quantities: { biere.id => "4" } }

    expect(response).to redirect_to(stay_bar_sheet_path(stay))
    expect(flash[:notice]).to include("1 ajoutée")
    expect(stay.reload.total_amount_cents).to eq(1_400)
  end

  it "joint puis retire une photo de la feuille" do
    photo = Rack::Test::UploadedFile.new(StringIO.new("fake-jpeg"), "image/jpeg", original_filename: "feuille.jpg")
    post photos_stay_bar_sheet_path(stay), params: { photos: [photo] }

    expect(response).to redirect_to(stay_bar_sheet_path(stay))
    expect(stay.reload.bar_sheet_photos).to be_attached

    delete photo_stay_bar_sheet_path(stay, photo_id: stay.bar_sheet_photos.first.id)
    expect(response).to redirect_to(stay_bar_sheet_path(stay))
  end

  it "refuse un fichier qui n'est pas une image" do
    pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF"), "application/pdf", original_filename: "feuille.pdf")
    post photos_stay_bar_sheet_path(stay), params: { photos: [pdf] }

    expect(flash[:alert]).to include("images")
    expect(stay.reload.bar_sheet_photos).not_to be_attached
  end

  it "montre les consommations dans le bloc « Bar » de la fiche séjour" do
    Stays::EncodeBarSheet.new(stay: stay, quantities: { biere.id => 4 }).run!

    get stay_path(stay)

    expect(response.body).to include("4 × Moinette")
    expect(response.body).to include("Modifier la feuille de bar")
  end
end
