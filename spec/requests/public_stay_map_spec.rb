require "rails_helper"

# Epic #348, phase 4 — la carte du domaine pour les hôtes, à la place du papier.
#
# `/sejour/:token/carte` : sans compte, protégée par le jeton du séjour. Elle
# sert le fond de carte, la couche Accueil dans la langue du séjour et le tracé
# du gîte de CE séjour — et rien d'autre : ni la Gestion, ni les gîtes des
# autres, ni aucune donnée d'un autre séjour.
RSpec.describe "Public /sejour/:token/carte — la carte des hôtes (epic #348, phase 4)", type: :request do
  let(:square) do
    { "type" => "Polygon",
      "coordinates" => [[[4.905, 50.340], [4.906, 50.340], [4.906, 50.341], [4.905, 50.340]]] }
  end
  let(:other_square) do
    { "type" => "Polygon",
      "coordinates" => [[[4.907, 50.341], [4.908, 50.341], [4.908, 50.342], [4.907, 50.341]]] }
  end
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << Room.create!(name: "Mélisse", level: 1)
    lodging
  end
  let!(:cheveche) do
    lodging = Lodging.create!(name: "La Chevêche", price_night_cents: 42_000)
    lodging.rooms << Room.create!(name: "Sauge", level: 1)
    lodging
  end
  let(:stay) { build_stay(hulotte) }

  def build_stay(lodging, email: "camille@example.com")
    draft = Reservations::Draft.new(
      lodging_id: lodging.id, arrival_date: (Date.current + 10).iso8601, departure_date: (Date.current + 12).iso8601,
      dogs_count: 0, first_name: "Camille", last_name: "Martin",
      email: email, phone: "+32470112233", halls: []
    )
    builder = Reservations::Builder.new(draft: draft, admin: true, status: "confirmed", source: "manual")
    builder.run!
    builder.stay
  end

  def install_base_layer
    MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20, default: true,
                         bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
  end

  def data_value(name)
    node = Nokogiri::HTML(response.body).at_css("[data-controller='public--stay-map']")
    JSON.parse(node["data-public--stay-map-#{name}-value"])
  end

  describe "la page" do
    before do
      install_base_layer
      welcome = MapLayer.for_kind(:welcome)
      welcome.map_features.create!(feature_kind: "zone", geometry: square,
                                   name_i18n: { "fr" => "Jardin des familles", "en" => "Families' garden" },
                                   description_i18n: { "fr" => "Espace privé des habitants" },
                                   properties: { "access" => "private" })
      welcome.map_features.create!(feature_kind: "point", geometry: { "type" => "Point", "coordinates" => [4.9055, 50.3405] },
                                   name_i18n: { "fr" => "Parking" }, properties: { "icon" => "parking" })
      MapLayer.for_kind(:management).map_features.create!(
        feature_kind: "zone", geometry: square, name_i18n: { "fr" => "Compost du collectif" },
        properties: { "management_notes" => "Retourner tous les quinze jours" }
      )
      venues = MapLayer.for_kind(:venues)
      venues.map_features.create!(feature_kind: "lodging", geometry: square, linked: hulotte)
      venues.map_features.create!(feature_kind: "lodging", geometry: other_square, linked: cheveche)
    end

    it "sert la couche Accueil, dans la langue du séjour, et le fond par jeton" do
      get public_stay_map_path(stay.token)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("translation missing")
      welcome = data_value("welcome")
      expect(welcome["features"].map { |f| f["properties"]["name"] }).to contain_exactly("Jardin des familles", "Parking")
      zone = welcome["features"].find { |f| f["properties"]["name"] == "Jardin des familles" }
      expect(zone["properties"]).to include("access" => "private", "description" => "Espace privé des habitants")
      tiles = Nokogiri::HTML(response.body).at_css("[data-controller='public--stay-map']")["data-public--stay-map-tiles-url-value"]
      expect(tiles).to eq("/map/tiles/test-layer/{kind}/{z}/{x}/{y}.png?sejour=#{stay.token}")
    end

    it "passe à l'anglais, avec repli sur le français" do
      get public_stay_map_path(stay.token, locale: "en")

      names = data_value("welcome")["features"].map { |f| f["properties"]["name"] }
      expect(names).to contain_exactly("Families' garden", "Parking")
      expect(response.body).to include("Map of the estate", "Open access")
    end

    it "surligne le gîte du séjour, et lui seul" do
      get public_stay_map_path(stay.token)

      lodgings = data_value("lodgings")["features"]
      expect(lodgings.map { |f| f["properties"]["name"] }).to eq(["La Hulotte"])
      expect(lodgings.first["geometry"]).to eq(square)
      expect(response.body).to include("Votre hébergement")
    end

    it "ne laisse passer ni la Gestion, ni les autres gîtes, ni un autre séjour" do
      other = build_stay(cheveche, email: "autre@example.com")

      get public_stay_map_path(stay.token)

      expect(response.body).not_to include("Compost du collectif", "Retourner tous les quinze jours", "La Chevêche")
      expect(response.body).not_to include(other.token, "autre@example.com")
    end

    it "revient vers la page du séjour" do
      get public_stay_map_path(stay.token)
      expect(response.body).to include(%(href="#{public_stay_path(stay.token)}"))
    end
  end

  it "répond 404 à un jeton inconnu" do
    install_base_layer
    get public_stay_map_path("jeton-inconnu")
    expect(response).to have_http_status(:not_found)
  end

  it "le dit simplement quand aucun fond de carte n'est installé" do
    get public_stay_map_path(stay.token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-map-unavailable="true"')
    expect(response.body).not_to include('data-controller="public--stay-map"')
  end

  describe "« Mon séjour »" do
    it "ouvre la carte depuis un bloc placé avant la boulangerie" do
      install_base_layer
      get public_stay_path(stay.token)

      expect(response.body).to include('data-stay-map="true"', public_stay_map_path(stay.token), "Ouvrir la carte")
      expect(response.body.index('data-stay-map="true"')).to be < response.body.index('data-stay-bakery="true"')
    end

    it "n'affiche pas le bloc sans fond de carte" do
      get public_stay_path(stay.token)
      expect(response.body).not_to include('data-stay-map="true"')
    end
  end

  describe "les tuiles" do
    let(:fixtures_root) { Rails.root.join("spec/fixtures/files/map-tiles/test-layer") }
    let(:tile_path) { "/map/tiles/test-layer/rgb/12/2103/1383.png" }

    before do
      install_base_layer
      cible = Rails.root.join("storage", "map-tiles", "test-layer")
      FileUtils.mkdir_p(cible)
      FileUtils.cp_r("#{fixtures_root}/.", cible)
    end

    after { FileUtils.rm_rf(Rails.root.join("storage", "map-tiles", "test-layer")) }

    it "sont servies sans compte avec le jeton d'un séjour" do
      get "#{tile_path}?sejour=#{stay.token}"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/png")
    end

    it "restent fermées sans jeton ou avec un jeton inconnu" do
      get tile_path
      expect(response).to have_http_status(:unauthorized).or redirect_to(new_user_session_path)

      get "#{tile_path}?sejour=jeton-inconnu"
      expect(response).to have_http_status(:unauthorized).or redirect_to(new_user_session_path)
    end
  end
end
