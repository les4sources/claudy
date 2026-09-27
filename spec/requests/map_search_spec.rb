require "rails_helper"

# Epic #348, phase 14 — la recherche par mode : `GET /map/search?mode=…&q=…`
# rend les identifiants des objets VIVANTS de la couche du mode qui répondent.
# Chaque mode cherche dans ses propres champs (décision 10 : pas de recherche
# globale).
RSpec.describe "Carte du domaine — recherche par mode (epic #348, phase 14)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "agent-recherche@les4sources.be", password: "password123") }
  let(:point) { { "type" => "Point", "coordinates" => [4.905, 50.340] } }
  let(:square) do
    { "type" => "Polygon",
      "coordinates" => [[[4.905, 50.340], [4.906, 50.340], [4.906, 50.341], [4.905, 50.340]]] }
  end

  def search(params)
    get map_search_path, params: params, headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  def feature(layer, kind: "point", name: nil, geometry: point, properties: {}, **attrs)
    MapFeature.create!(map_layer: layer, feature_kind: kind, geometry: geometry,
                       name_i18n: name ? { "fr" => name } : {}, properties: properties, **attrs)
  end

  it "exige une session Devise" do
    get map_search_path, params: { mode: "management", q: "ortie" }, headers: { "Accept" => "application/json" }
    expect(response).not_to have_http_status(:ok)
  end

  context "connecté" do
    before { sign_in user }

    it "la page carte porte le champ de recherche et les filtres des plantes" do
      MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                           bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
      Plant.create!(name: "Cassis", status: "planted", zone: "Potager")
      get map_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-map-search", %(data-url="#{map_search_path}"), "data-map-search-input")
      expect(response.body).to include("Filtres des plantes", "Se récolte en", "A une tâche en", "Potager", "Inquiétante")
    end

    it "refuse un mode inconnu (422) et rend une liste vide sans critère" do
      get map_search_path, params: { mode: "globale", q: "x" }, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)

      body = search(mode: "management", q: "  ")
      expect(body).to eq("mode" => "management", "count" => 0, "feature_ids" => [])
    end

    describe "mode Gestion" do
      let(:management) { MapLayer.for_kind(:management) }

      it "cherche dans le nom, la consigne et le libellé des tâches, sur les objets vivants de la couche" do
        by_name = feature(management, kind: "zone", geometry: square, name: "Prairie des orties")
        by_notes = feature(management, kind: "zone", geometry: square, name: "Talus",
                                       properties: { "management_notes" => "Faucher les ORTIES en juin" })
        by_task = feature(management, kind: "zone", geometry: square, name: "Bosquet")
        MapTask.create!(subject: by_task, label: "Arracher les orties", months: [6])
        feature(management, kind: "zone", geometry: square, name: "Verger")
        dead = feature(management, kind: "zone", geometry: square, name: "Orties disparues")
        dead.soft_delete!(validate: false)
        feature(MapLayer.for_kind(:welcome), name: "Orties d'accueil")

        body = search(mode: "management", q: "ortie")
        expect(body["mode"]).to eq("management")
        expect(body["feature_ids"]).to contain_exactly(by_name.id, by_notes.id, by_task.id)
        expect(body["count"]).to eq(3)
      end

      it "échappe les jokers SQL de la saisie" do
        feature(management, name: "Mare")
        expect(search(mode: "management", q: "%")["feature_ids"]).to be_empty
      end
    end

    describe "mode Plantes" do
      let(:plants_layer) { MapLayer.for_kind(:plants) }
      let(:pommier) { PlantSpecies.create!(name: "Pommier", latin_name: "Malus domestica") }

      def placed_plant(attrs)
        plant = Plant.create!({ status: "planted" }.merge(attrs))
        point_feature = feature(plants_layer, kind: "plant")
        plant.update!(map_feature: point_feature)
        [plant, point_feature]
      end

      it "cherche par nom, espèce, variété, numéro et zone, parmi les plantes placées" do
        variety = PlantVariety.create!(plant_species: pommier, name: "Reinette Hernaut")
        _, reinette = placed_plant(name: "Pommier du haut", plant_species: pommier, plant_variety: variety, number: 12)
        _, noisetier = placed_plant(name: "Noisetier", number: 7, zone: "Verger")
        Plant.create!(name: "Pommier à placer", status: "to_place", plant_species: pommier)

        expect(search(mode: "plants", q: "malus")["feature_ids"]).to eq([reinette.id])
        expect(search(mode: "plants", q: "hernaut")["feature_ids"]).to eq([reinette.id])
        expect(search(mode: "plants", q: "#12")["feature_ids"]).to eq([reinette.id])
        expect(search(mode: "plants", q: "verger")["feature_ids"]).to eq([noisetier.id])
        expect(search(mode: "plants", q: "pommier")["feature_ids"]).to eq([reinette.id])
      end

      describe "filtres" do
        let(:verger_ids) { [@saine[1].id, @malade[1].id] }

        before do
          @saine = placed_plant(name: "Pommier sain", plant_species: pommier, health: "healthy", stratum: "tree", zone: "Verger")
          @malade = placed_plant(name: "Poirier malade", health: "sick", stratum: "tree", zone: "Verger", status: "to_move")
          @arbuste = placed_plant(name: "Cassis", health: "healthy", stratum: "shrub", zone: "Potager")
        end

        it "filtre par santé, statut, strate et zone, combinables avec le texte" do
          expect(search(mode: "plants", health: "healthy")["feature_ids"]).to contain_exactly(@saine[1].id, @arbuste[1].id)
          expect(search(mode: "plants", status: "to_move")["feature_ids"]).to eq([@malade[1].id])
          expect(search(mode: "plants", stratum: "shrub")["feature_ids"]).to eq([@arbuste[1].id])
          expect(search(mode: "plants", zone: "Verger")["feature_ids"]).to match_array(verger_ids)
          expect(search(mode: "plants", zone: "Verger", health: "healthy")["feature_ids"]).to eq([@saine[1].id])
          expect(search(mode: "plants", q: "poirier", stratum: "tree")["feature_ids"]).to eq([@malade[1].id])
          expect(search(mode: "plants", q: "poirier", stratum: "shrub")["feature_ids"]).to be_empty
        end

        it "« se récolte en » suit les fenêtres de la plante, sinon celles de son espèce" do
          pommier.harvest_windows.create!(part: "fruit", months: [9, 10])
          @arbuste[0].harvest_windows.create!(part: "fruit", months: [7])

          expect(search(mode: "plants", harvest_month: 9)["feature_ids"]).to eq([@saine[1].id])
          expect(search(mode: "plants", harvest_month: 7)["feature_ids"]).to eq([@arbuste[1].id])
          expect(search(mode: "plants", harvest_month: 7, zone: "Verger")["feature_ids"]).to be_empty
        end

        it "« a une tâche en » lit les tâches de la plante et de son point" do
          MapTask.create!(subject: @malade[0], label: "Tailler", months: [2])
          MapTask.create!(subject: @arbuste[1], label: "Pailler", months: [2, 11])

          expect(search(mode: "plants", task_month: 2)["feature_ids"]).to contain_exactly(@malade[1].id, @arbuste[1].id)
          expect(search(mode: "plants", task_month: 11, q: "cassis")["feature_ids"]).to eq([@arbuste[1].id])
          expect(search(mode: "plants", task_month: 5)["feature_ids"]).to be_empty
        end

        it "ignore une valeur de filtre inconnue plutôt que de tout rendre" do
          expect(search(mode: "plants", health: "radieuse", task_month: 13)["feature_ids"]).to be_empty
          expect(search(mode: "management", health: "healthy")["feature_ids"]).to be_empty
        end
      end
    end

    describe "mode Réseaux" do
      let(:water) { MapLayer.ensure_networks!.find { |layer| layer.network == "water" } }
      let(:electric) { MapLayer.ensure_networks!.find { |layer| layer.network == "electric" } }

      it "cherche dans le nom, le type de nœud (libellé) et la consigne" do
        vanne = feature(water, kind: "node", name: "V1", properties: { "node_type" => "valve" })
        citerne = feature(water, kind: "node", name: "Citerne nord", properties: { "node_type" => "cistern" })
        consigne = feature(water, kind: "node", name: "R2",
                                  properties: { "node_type" => "tap", "instructions" => "Purger avant l'hiver" })
        tableau = feature(electric, kind: "node", name: "Tableau gîte", properties: { "node_type" => "panel" })

        expect(search(mode: "network", q: "vanne")["feature_ids"]).to eq([vanne.id])
        expect(search(mode: "network", q: "citerne")["feature_ids"]).to eq([citerne.id])
        expect(search(mode: "network", q: "purger")["feature_ids"]).to eq([consigne.id])
        expect(search(mode: "network", q: "tableau")["feature_ids"]).to eq([tableau.id])
        # La couche réseau active restreint la recherche à son réseau.
        expect(search(mode: "network", q: "tableau", layer_id: water.id)["feature_ids"]).to be_empty
      end
    end

    describe "mode Commentaires" do
      let(:comments) { MapLayer.for_kind(:comments) }

      it "cherche dans le corps de tous les messages vivants du fil" do
        fil = feature(comments, kind: "comment")
        root = MapComment.create!(map_feature: fil, author: user, body: "La clôture est tombée")
        MapComment.create!(map_feature: fil, author: user, parent: root, body: "Réparée avec du fil de fer")
        autre = feature(comments, kind: "comment")
        effacé = MapComment.create!(map_feature: autre, author: user, body: "Fil barbelé")
        effacé.soft_delete!(validate: false)

        expect(search(mode: "comments", q: "fer")["feature_ids"]).to eq([fil.id])
        expect(search(mode: "comments", q: "barbelé")["feature_ids"]).to be_empty
      end
    end

    describe "mode Biodiversité" do
      let(:biodiversity) { MapLayer.for_kind(:biodiversity) }

      it "cherche dans l'espèce commune et latine" do
        releve = feature(biodiversity, kind: "observation", created_by: user,
                                       properties: { "realm" => "fauna", "species_common" => "Chouette hulotte",
                                                     "species_latin" => "Strix aluco" })
        feature(biodiversity, kind: "observation", created_by: user,
                              properties: { "realm" => "flora", "species_common" => "Ail des ours" })

        expect(search(mode: "biodiversity", q: "hulotte")["feature_ids"]).to eq([releve.id])
        expect(search(mode: "biodiversity", q: "strix")["feature_ids"]).to eq([releve.id])
      end
    end

    describe "mode Accueil" do
      let(:welcome) { MapLayer.for_kind(:welcome) }

      it "cherche dans le nom et la description, toutes langues" do
        parking = feature(welcome, name: "Parking", properties: { "icon" => "parking" })
        four = feature(welcome, name: "Four", properties: { "icon" => "oven" },
                                description_i18n: { "fr" => "Le grand four à bois", "en" => "Wood-fired oven" })

        expect(search(mode: "welcome", q: "parking")["feature_ids"]).to eq([parking.id])
        expect(search(mode: "welcome", q: "wood")["feature_ids"]).to eq([four.id])
      end
    end

    describe "mode Lieux" do
      let(:venues) { MapLayer.for_kind(:venues) }
      let!(:hulotte) do
        lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
        lodging.rooms << Room.create!(name: "Mélisse", level: 1)
        lodging
      end
      let!(:salle) { Space.create!(name: "Grande Salle", capacity: 1) }

      it "cherche dans le nom du gîte ou de la salle, et le client présent au jour choisi" do
        trace_hulotte = feature(venues, kind: "zone", geometry: square, venue_keys: ["Lodging:#{hulotte.id}"])
        trace_salle = feature(venues, kind: "zone", geometry: square, venue_keys: ["Space:#{salle.id}"])

        draft = Reservations::Draft.new(
          lodging_id: hulotte.id, arrival_date: Date.current.iso8601, departure_date: (Date.current + 2).iso8601,
          dogs_count: 0, first_name: "Camille", last_name: "Martin",
          email: "camille@example.com", phone: "+32470112233", halls: []
        )
        Reservations::Builder.new(draft: draft, admin: true, status: "confirmed", source: "manual").run!

        expect(search(mode: "venues", q: "hulotte")["feature_ids"]).to eq([trace_hulotte.id])
        expect(search(mode: "venues", q: "salle")["feature_ids"]).to eq([trace_salle.id])
        expect(search(mode: "venues", q: "martin", date: Date.current.iso8601)["feature_ids"]).to eq([trace_hulotte.id])
        expect(search(mode: "venues", q: "martin", date: (Date.current + 10).iso8601)["feature_ids"]).to be_empty
      end
    end
  end
end
