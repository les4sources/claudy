require "rails_helper"

# L'orthophoto du domaine partagée avec Semisto Designer : sans session, un
# jeton `?partage=` ouvre la photo (`rgb`) et rien d'autre.
RSpec.describe "Tuiles de la carte partagées avec Semisto Designer", type: :request do
  let(:fixtures_root) { Rails.root.join("spec/fixtures/files/map-tiles/test-layer") }
  let(:token) { "jeton-de-partage-de-test" }
  let(:tile) { "/map/tiles/share-layer/rgb/12/2103/1383.png" }

  before do
    cible = Rails.root.join("storage", "map-tiles", "share-layer")
    FileUtils.mkdir_p(cible)
    FileUtils.cp_r("#{fixtures_root}/.", cible)
    MapBaseLayer.create!(key: "share-layer", name: "Couche partagée", captured_on: Date.new(2023, 5, 1))
  end

  after { FileUtils.rm_rf(Rails.root.join("storage", "map-tiles", "share-layer")) }

  around do |example|
    previous = ENV.to_h.slice("MAP_TILES_SHARE_TOKEN", "MAP_TILES_SHARE_ORIGINS")
    ENV["MAP_TILES_SHARE_TOKEN"] = token
    ENV.delete("MAP_TILES_SHARE_ORIGINS")
    example.run
  ensure
    ENV.delete("MAP_TILES_SHARE_TOKEN")
    previous.each { |key, value| ENV[key] = value }
  end

  it "sert la photo avec le bon jeton, sans session, et l'ouvre à Designer" do
    get "#{tile}?partage=#{token}", headers: { "Origin" => "https://designer.semisto.org" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.headers["Access-Control-Allow-Origin"]).to eq("https://designer.semisto.org")
  end

  it "ne pose pas l'en-tête CORS pour une autre origine" do
    get "#{tile}?partage=#{token}", headers: { "Origin" => "https://ailleurs.example" }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
  end

  it "refuse un mauvais jeton" do
    get "#{tile}?partage=mauvais"

    expect(response).to have_http_status(:unauthorized)
  end

  it "n'ouvre pas le relief, même avec le jeton" do
    get "/map/tiles/share-layer/dem/12/2103/1383.png?partage=#{token}"

    expect(response).to have_http_status(:unauthorized)
  end

  it "n'ouvre rien quand la variable n'est pas posée" do
    ENV.delete("MAP_TILES_SHARE_TOKEN")

    get "#{tile}?partage="

    expect(response).to have_http_status(:unauthorized)
  end
end
