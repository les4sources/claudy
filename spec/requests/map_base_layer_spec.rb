require "rails_helper"
require "rake"

# Epic #348, phase 1 — le fond de carte et la page Carte.
#
# 15 hectares dont l'orthophoto vivait chez un tiers dont on n'a plus le compte.
# Cette phase rapatrie le fond dans Claudy : une table de couches datées, des
# tuiles servies par l'app depuis `storage/map-tiles/`, et une page plein écran.
RSpec.describe "Carte du domaine — fond de carte (epic #348, phase 1)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-map@les4sources.be", password: "password123") }
  let(:fixtures_root) { Rails.root.join("spec/fixtures/files/map-tiles/test-layer") }

  # Les tuiles vivent hors du dépôt, sous `storage/map-tiles/`. Les specs y
  # écrivent une couche jetable et la retirent : sans ça, un test raterait sur
  # la machine de quelqu'un qui n'a pas importé le vrai vol.
  def install_tiles(key)
    cible = Rails.root.join("storage", "map-tiles", key)
    FileUtils.mkdir_p(cible)
    FileUtils.cp_r("#{fixtures_root}/.", cible)
    cible
  end

  def remove_tiles(key)
    FileUtils.rm_rf(Rails.root.join("storage", "map-tiles", key))
  end

  def build_layer(key: "test-layer", **attrs)
    MapBaseLayer.create!({
      key: key, name: "Couche de test", captured_on: Date.new(2023, 5, 1),
      min_zoom: 12, max_zoom: 20,
      bounds: { "south" => 50.3392832, "west" => 4.9031066, "north" => 50.3435344, "east" => 4.9126003 }
    }.merge(attrs))
  end

  before { sign_in user }

  describe "le modèle MapBaseLayer" do
    it "exige une clé unique" do
      build_layer
      doublon = MapBaseLayer.new(key: "test-layer", name: "Autre")

      expect(doublon).not_to be_valid
    end

    # La clé est un SEGMENT DE CHEMIN vers `storage/map-tiles/` : elle se
    # défend ici, avant que le contrôleur de tuiles n'ait à s'en méfier.
    it "refuse une clé qui pourrait remonter l'arborescence" do
      expect(MapBaseLayer.new(key: "../../etc", name: "Vilaine")).not_to be_valid
      expect(MapBaseLayer.new(key: "Ahinvaux 2023", name: "Espaces")).not_to be_valid
      expect(MapBaseLayer.new(key: "ahinvaux-2023", name: "Correcte")).to be_valid
    end

    it "rend l'emprise dans l'ordre de Leaflet et le centre du domaine" do
      couche = build_layer

      expect(couche.leaflet_bounds).to eq([[50.3392832, 4.9031066], [50.3435344, 4.9126003]])
      expect(couche.center.first).to be_within(0.0001).of(50.3414088)
      expect(couche.center.last).to be_within(0.0001).of(4.9078535)
    end

    it "trie les fonds du plus récent au plus ancien" do
      vieux = build_layer(key: "vol-2023", captured_on: Date.new(2023, 5, 1))
      neuf = build_layer(key: "vol-2027", captured_on: Date.new(2027, 4, 1))

      expect(MapBaseLayer.ordered.to_a).to eq([neuf, vieux])
    end

    describe ".default_layer" do
      it "rend celle qui porte le drapeau" do
        build_layer(key: "vol-2027", captured_on: Date.new(2027, 4, 1))
        marquee = build_layer(key: "vol-2023", captured_on: Date.new(2023, 5, 1), default: true)

        expect(MapBaseLayer.default_layer).to eq(marquee)
      end

      it "rend la plus récente quand personne ne porte le drapeau" do
        build_layer(key: "vol-2023", captured_on: Date.new(2023, 5, 1))
        neuf = build_layer(key: "vol-2027", captured_on: Date.new(2027, 4, 1))

        expect(MapBaseLayer.default_layer).to eq(neuf)
      end

      it "ne rend rien quand aucune couche n'existe" do
        expect(MapBaseLayer.default_layer).to be_nil
      end
    end

    # Deux drapeaux laisseraient le choix au hasard de l'ordre SQL.
    it "n'a jamais deux fonds par défaut" do
      premier = build_layer(key: "vol-2023", default: true)
      second = build_layer(key: "vol-2027", default: true)

      expect(premier.reload.default?).to be(false)
      expect(second.reload.default?).to be(true)
      expect(MapBaseLayer.where(default: true).count).to eq(1)
    end
  end

  describe "GET /map/tiles/:key/:kind/:z/:x/:y.png" do
    before { install_tiles("test-layer") }
    after { remove_tiles("test-layer") }

    it "sert la tuile en PNG avec un cache long" do
      build_layer

      get "/map/tiles/test-layer/rgb/12/2103/1383.png"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/png")
      expect(response.headers["Cache-Control"]).to include("immutable")
    end

    it "sert aussi le relief" do
      build_layer

      get "/map/tiles/test-layer/dem/12/2103/1383.png"

      expect(response).to have_http_status(:ok)
    end

    # Une tuile absente est NORMALE en bord d'emprise : Leaflet en demande tout
    # un carré, le vol n'en couvre qu'une partie. 404, jamais 500.
    it "répond 404 sur une tuile absente, sans erreur serveur" do
      build_layer

      get "/map/tiles/test-layer/rgb/12/9999/9999.png"

      expect(response).to have_http_status(:not_found)
    end

    it "répond 404 sur une couche inconnue" do
      get "/map/tiles/inexistante/rgb/12/2103/1383.png"

      expect(response).to have_http_status(:not_found)
    end

    it "répond 404 sur un type de tuile inconnu" do
      build_layer

      get "/map/tiles/test-layer/secret/12/2103/1383.png"

      expect(response).to have_http_status(:not_found)
    end

    # La clé vient de la BASE, les z/x/y sont des entiers : rien dans l'URL ne
    # peut remonter hors de `storage/map-tiles/`. Le routeur refuse déjà une
    # clé encodée qui contient des séparateurs — la requête n'atteint même pas
    # le contrôleur.
    it "ne laisse pas remonter l'arborescence" do
      build_layer

      expect { get "/map/tiles/..%2F..%2Fconfig/rgb/12/2103/1383.png" }
        .to raise_error(ActionController::RoutingError)
    end

    # Et si une clé douteuse atteignait quand même le contrôleur, elle ne
    # correspondrait à aucune ligne de `map_base_layers`.
    it "refuse une clé absente de la table" do
      build_layer

      get "/map/tiles/storage/rgb/12/2103/1383.png"

      expect(response).to have_http_status(:not_found)
    end

    # Une tuile n'est pas une page : Devise répond 401 plutôt que de rediriger
    # vers le formulaire de connexion, et c'est ce qu'il faut — Leaflet ne sait
    # pas quoi faire d'un formulaire HTML.
    it "exige une session" do
      build_layer
      sign_out user

      get "/map/tiles/test-layer/rgb/12/2103/1383.png"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /map" do
    it "affiche la carte plein écran avec le fond par défaut" do
      couche = build_layer(default: true)

      get map_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="map"')
      expect(response.body).to include("/map/tiles/#{couche.key}/{kind}/{z}/{x}/{y}.png")
      expect(response.body).to include("Couches")
      expect(response.body).to include("Ma position")
    end

    it "liste les fonds disponibles, du plus récent au plus ancien" do
      build_layer(key: "vol-2023", name: "Ahinvaux (mai 2023)", captured_on: Date.new(2023, 5, 1))
      build_layer(key: "vol-2027", name: "Ahinvaux (avril 2027)", captured_on: Date.new(2027, 4, 1))

      get map_path

      expect(response.body.index("Ahinvaux (avril 2027)")).to be < response.body.index("Ahinvaux (mai 2023)")
    end

    it "permet de choisir un fond plus ancien" do
      build_layer(key: "vol-2027", captured_on: Date.new(2027, 4, 1), default: true)
      vieux = build_layer(key: "vol-2023", name: "Ahinvaux (mai 2023)", captured_on: Date.new(2023, 5, 1))

      get map_path(base_layer_id: vieux.id)

      expect(response.body).to include("/map/tiles/vol-2023/{kind}/{z}/{x}/{y}.png")
    end

    # La bascule Relief n'a de sens que pour une couche qui en a.
    it "n'offre le relief que quand la couche en a" do
      build_layer(has_relief: false)
      get map_path
      expect(response.body).not_to include("Relief")

      MapBaseLayer.update_all(has_relief: true)
      get map_path
      expect(response.body).to include("Relief")
    end

    # Aucun fond installé n'est pas une erreur : c'est l'état d'une production
    # fraîchement déployée, avant que la tâche rake ne tourne.
    it "explique quoi faire quand aucun fond n'est installé" do
      get map_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Aucun fond de carte n'est installé")
      expect(response.body).to include("map:base_layer:import")
    end

    it "pose l'entrée « Carte » dans la navbar" do
      build_layer

      get map_path

      expect(response.body).to include(">Carte</span>")
    end

    it "exige une session" do
      sign_out user

      get map_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "rake map:base_layer:import" do
    let(:key) { "spec-import-layer" }

    before do
      Rails.application.load_tasks if Rake::Task.tasks.empty?
      Rake::Task["map:base_layer:import"].reenable
    end

    after do
      remove_tiles(key)
      %w[KEY NAME DATE SRC DEFAULT].each { |var| ENV.delete(var) }
    end

    def run_import(**env)
      env.each { |k, v| ENV[k.to_s] = v.to_s }
      Rake::Task["map:base_layer:import"].reenable
      Rake::Task["map:base_layer:import"].invoke
    end

    it "crée la couche depuis metadata.json et copie les tuiles" do
      silence_stream { run_import(KEY: key, NAME: "Couche importée", DATE: "2023-05-01", SRC: fixtures_root.to_s) }

      couche = MapBaseLayer.find_by(key: key)
      expect(couche.name).to eq("Couche importée")
      expect(couche.captured_on).to eq(Date.new(2023, 5, 1))
      expect(couche.min_zoom).to eq(12)
      expect(couche.max_zoom).to eq(20)
      expect(couche.bounds).to eq("south" => 50.3392832, "west" => 4.9031066,
                                  "north" => 50.3435344, "east" => 4.9126003)
      expect(couche.has_relief).to be(true)
      expect(couche.tiles_root.join("rgb", "12", "2103", "1383.png")).to exist
      expect(couche.tiles_root.join("dem", "12", "2103", "1383.png")).to exist
    end

    # Relancée sur la même source, elle met à jour — elle ne duplique jamais,
    # et n'imbrique pas `rgb/rgb`.
    it "est idempotente" do
      silence_stream { run_import(KEY: key, NAME: "Première", SRC: fixtures_root.to_s) }
      silence_stream { run_import(KEY: key, NAME: "Seconde", SRC: fixtures_root.to_s) }

      expect(MapBaseLayer.where(key: key).count).to eq(1)
      expect(MapBaseLayer.find_by(key: key).name).to eq("Seconde")
      expect(Rails.root.join("storage", "map-tiles", key, "rgb", "rgb")).not_to exist
    end

    it "pose le drapeau par défaut avec DEFAULT=1" do
      autre = build_layer(key: "autre-fond", default: true)

      silence_stream { run_import(KEY: key, NAME: "Nouvelle", SRC: fixtures_root.to_s, DEFAULT: "1") }

      expect(MapBaseLayer.find_by(key: key).default?).to be(true)
      expect(autre.reload.default?).to be(false)
    end
  end

  # La tâche écrit sur `$stdout` : sans ça la sortie des specs est illisible.
  def silence_stream
    original = $stdout
    # `StringIO.new` sans argument part en ASCII-8BIT : la tâche y écrit des
    # guillemets français et Ruby refuse le mélange d'encodages.
    $stdout = StringIO.new(String.new(encoding: Encoding::UTF_8))
    yield
  ensure
    $stdout = original
  end
end
