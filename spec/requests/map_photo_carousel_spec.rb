require "rails_helper"

# Toute fiche de la carte qui a des photos les montre en carousel en tête de
# fiche, avec le plein écran (`shared/_photo_carousel`) : objets de toutes les
# couches, relevés de bio-indicatrices, plantes nourricières. Le relevé de
# biodiversité a le sien, photos d'observations.be comprises
# (`map_observations_imported_spec`).
RSpec.describe "Carte du domaine — carousel des photos", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-carousel@les4sources.be", password: "password123") }
  let(:point) { { "type" => "Point", "coordinates" => [4.9078, 50.3414] } }

  before { sign_in user }

  def attach_photos(record, count)
    count.times do
      record.photos.attach(Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/capture.png"), "image/png"))
    end
  end

  def carousel
    Nokogiri::HTML(response.body).at_css("[data-controller='photo-carousel']")
  end

  def expect_carousel_of(count)
    expect(carousel).to be_present
    expect(carousel.css("[data-photo-carousel-target='track'] img").size).to eq(count)
    expect(carousel.at_css("dialog[data-photo-carousel-target='dialog']").css("img").size).to eq(count)
  end

  it "un objet de la couche Gestion" do
    feature = MapLayer.for_kind(:management).map_features.create!(feature_kind: "point", geometry: point)
    get map_feature_path(feature)
    expect(carousel).to be_nil

    attach_photos(feature, 2)
    get map_feature_path(feature)
    expect_carousel_of(2)
  end

  it "un relevé de bio-indicatrices" do
    record = MapLayer.for_kind(:bioindicators).map_features.create!(feature_kind: "bioindicator", geometry: point)
    attach_photos(record, 3)
    get map_feature_path(record)
    expect_carousel_of(3)
  end

  it "une plante nourricière, en tête de fiche" do
    plant = Plant.create!(name: "Pommier du haut", number: 7)
    get plant_path(plant)
    expect(carousel).to be_nil

    attach_photos(plant, 2)
    get plant_path(plant)
    expect_carousel_of(2)
    expect(carousel.ancestors("header")).to be_present
  end
end
