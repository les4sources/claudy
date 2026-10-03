require "rails_helper"

# Un relevé importé d'observations.be : sa fiche dit d'où il vient, qui l'a
# observé, et renvoie à la fiche d'origine.
RSpec.describe "Carte du domaine — relevé importé d'observations.be", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-obs@les4sources.be", password: "password123") }
  let(:layer) { MapLayer.for_kind(:biodiversity) }
  let!(:record) do
    layer.map_features.create!(
      feature_kind: "observation", geometry: { "type" => "Point", "coordinates" => [4.90769, 50.341339] },
      properties: { "realm" => "fungi", "species_common" => "Lépiote élevée", "species_latin" => "Macrolepiota procera",
                    "observed_on" => "2023-09-30", "count" => 12, "source" => "observations.be", "source_id" => "289302713",
                    "source_url" => "https://observations.be/observation/289302713/", "observer_name" => "François Hela",
                    "photos_count" => 2,
                    "photo_urls" => ["https://observations.be/media/photo/78263003.jpg",
                                     "https://observations.be/media/photo/78263004.jpg"] }
    )
  end

  before { sign_in user }

  it "montre la source, l'observateur externe et le lien vers la fiche d'origine" do
    get map_feature_path(record)

    page = Nokogiri::HTML(response.body)
    source = page.at_css("[data-observation-source]")
    expect(source.text).to include("Importé d'observations.be", "François Hela", "2 photos")
    link = source.at_css("a")
    expect(link["href"]).to eq("https://observations.be/observation/289302713/")
    expect(link["target"]).to eq("_blank")
    expect(page.at_css("[data-observation-external-observer]").text).to eq("François Hela")
    expect(page.at_css("select[name='observation[observer_id]']")).to be_nil
    expect(page.css("input[name='observation[realm]']").map { |input| input["value"] }).to include("fungi")
  end

  it "montre les photos d'observations.be en carousel, depuis leur adresse d'origine, créditées" do
    get map_feature_path(record)

    page = Nokogiri::HTML(response.body)
    carousel = page.at_css("[data-controller='photo-carousel']")
    slides = carousel.css("[data-photo-carousel-target='track'] img")
    expect(slides.map { |img| img["src"] }).to eq(["https://observations.be/media/photo/78263003.jpg",
                                                   "https://observations.be/media/photo/78263004.jpg"])
    expect(slides.map { |img| img["referrerpolicy"] }).to all(eq("no-referrer"))
    expect(carousel.at_css("dialog[data-photo-carousel-target='dialog']").css("img").size).to eq(2)
    expect(carousel.at_css("[data-photo-carousel-target='counter']").text).to eq("1 / 2")
    expect(page.at_css("[data-observation-photo-credit]").text).to include("observations.be", "François Hela")
  end

  it "met les photos ajoutées ici avant celles d'observations.be, sans referrerpolicy" do
    record.photos.attach(Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/capture.png"), "image/png"))

    get map_feature_path(record)

    slides = Nokogiri::HTML(response.body).css("[data-photo-carousel-target='track'] img")
    expect(slides.size).to eq(3)
    expect(slides.first["src"]).not_to include("observations.be")
    expect(slides.first["referrerpolicy"]).to be_nil
  end

  it "ignore une adresse de photo qui n'est pas https" do
    record.update!(properties: record.properties.merge("photo_urls" => ["javascript:alert(1)"]))

    get map_feature_path(record)

    expect(response.body).not_to include("data-photo-carousel", "javascript:alert")
  end

  it "refuse un lien de source qui n'est pas une adresse web" do
    record.properties = record.properties.merge("source_url" => "javascript:alert(1)")

    expect(record).not_to be_valid
    expect(record.errors.full_messages.join).to include("adresse web")
  end
end
