require "rails_helper"

# La spec OpenAPI est écrite à la main (config/openapi/v1.yaml) : rien ne la
# garde cohérente, sinon ceci. Validité structurelle (références, paramètres de
# chemin, tags), chemins réellement routés, et — pour la carte (epic #348,
# phase 8) — des listes fermées identiques à celles des modèles.
RSpec.describe "Api::V1 OpenAPI", type: :request do
  let(:token) { "test-token-openapi" }
  let(:auth) { { "Authorization" => "Bearer #{token}" } }
  let(:spec) do
    get "/api/v1/openapi", headers: auth
    JSON.parse(response.body)
  end
  let(:operations) do
    spec["paths"].flat_map do |path, item|
      item.slice("get", "post", "put", "patch", "delete").map { |verb, operation| [path, verb, operation, item] }
    end
  end

  around do |example|
    previous = ENV["AGENT_API_TOKEN"]
    ENV["AGENT_API_TOKEN"] = token
    example.run
    ENV["AGENT_API_TOKEN"] = previous
  end

  def refs_in(node, found = [])
    case node
    when Hash
      found << node["$ref"] if node["$ref"].is_a?(String)
      node.each_value { |value| refs_in(value, found) }
    when Array then node.each { |value| refs_in(value, found) }
    end
    found
  end

  def resolve(node)
    return node unless node.is_a?(Hash) && node["$ref"]

    node["$ref"].delete_prefix("#/").split("/").reduce(spec) { |memo, key| memo.fetch(key) }
  end

  it "est un document OpenAPI 3 dont toutes les références se résolvent" do
    expect(spec["openapi"]).to start_with("3.")
    unresolved = refs_in(spec).uniq.reject do |ref|
      ref.start_with?("#/") && ref.delete_prefix("#/").split("/").reduce(spec) { |memo, key| memo.is_a?(Hash) ? memo[key] : nil }
    end
    expect(unresolved).to be_empty
  end

  it "donne des réponses à chaque opération et déclare chaque paramètre de chemin" do
    problems = operations.flat_map do |path, verb, operation, item|
      declared = (Array(item["parameters"]) + Array(operation["parameters"])).map { |param| resolve(param) }
                                                                             .select { |param| param["in"] == "path" }
                                                                             .map { |param| param["name"] }
      missing = path.scan(/\{(\w+)\}/).flatten - declared
      issues = missing.map { |name| "#{verb.upcase} #{path} : paramètre {#{name}} non déclaré" }
      issues << "#{verb.upcase} #{path} : pas de réponses" if operation["responses"].blank?
      issues
    end
    expect(problems).to be_empty
  end

  it "n'utilise que des tags déclarés" do
    declared = spec["tags"].map { |tag| tag["name"] }
    used = operations.flat_map { |_, _, operation, _| Array(operation["tags"]) }.uniq
    expect(used - declared).to be_empty
  end

  describe "carte et plantes (epic #348, phase 8)" do
    let(:expected) do
      {
        "/plant_species" => %w[get post], "/plant_species/{id}" => %w[get patch],
        "/plant_varieties" => %w[get post], "/plant_varieties/{id}" => %w[get],
        "/plants" => %w[get post], "/plants/{id}" => %w[get patch delete],
        "/plants/{plant_id}/notes" => %w[post], "/plants/{plant_id}/photos" => %w[post],
        "/plants/{plant_id}/photos/{id}" => %w[delete],
        "/map_features" => %w[get post], "/map_features/{id}" => %w[get patch delete],
        "/map_features/{map_feature_id}/notes" => %w[post], "/map_features/{map_feature_id}/photos" => %w[post],
        "/map_features/{map_feature_id}/photos/{id}" => %w[delete],
        "/map_notes/{id}" => %w[patch delete],
        "/map_tasks" => %w[get post], "/map_tasks/{id}" => %w[get patch delete]
      }
    end

    it "décrit chaque chemin avec ses verbes, et chacun est routé" do
      expected.each do |path, verbs|
        expect(spec["paths"][path]&.keys.to_a & %w[get post put patch delete]).to match_array(verbs), path
        verbs.each do |verb|
          route = Rails.application.routes.recognize_path("/api/v1#{path.gsub(/\{\w+\}/, '1')}", method: verb)
          expect(route[:controller]).to start_with("api/v1/"), "#{verb} #{path}"
        end
      end
    end

    it "les annonce dans l'index de découverte" do
      get "/api/v1", headers: auth
      expect(JSON.parse(response.body)["resources"].map { |r| r["name"] })
        .to include("plant_species", "plant_varieties", "plants", "map_features", "map_notes", "map_tasks")
    end

    it "décrit les schémas des ressources" do
      expect(spec["components"]["schemas"]).to include("Plant", "PlantDetail", "PlantInput", "PlantSpecies",
                                                       "PlantVariety", "HarvestWindow", "MapNote", "MapFeature",
                                                       "MapTask", "Photo")
      expect(spec.dig("components", "schemas", "Plant", "properties").keys)
        .to include("id", "created_at", "updated_at", "number", "latitude", "longitude", "placed", "species",
                    "variety", "harvest_windows_effective")
    end

    it "reprend exactement les listes fermées des modèles" do
      enum = ->(name) { spec.dig("components", "schemas", name, "enum") }
      expect(enum.call("PlantStatus")).to eq(Plant::STATUSES.keys)
      expect(enum.call("PlantHealth")).to eq(Plant::HEALTHS.keys)
      expect(enum.call("PlantProduction")).to eq(Plant::PRODUCTIONS.keys)
      expect(enum.call("PlantHabit")).to eq(Plant::HABITS.keys)
      expect(enum.call("PlantStratum")).to eq(Plant::STRATA.keys)
      expect(enum.call("PlantPopulation")).to eq(Plant::POPULATIONS.keys)
      expect(enum.call("PlantStockType")).to eq(Plant::STOCK_TYPES.keys)
      expect(enum.call("HarvestPart")).to eq(PlantHarvestWindow::PARTS.keys)
      expect(enum.call("MapFeatureKind")).to eq(MapFeature::FEATURE_KINDS)
      expect(enum.call("MapLayerKind")).to eq(MapLayer::KINDS)
      expect(enum.call("MapTaskSector")).to eq(MapTask::SECTORS.keys)
      expect(enum.call("MapSubjectType")).to eq(MapTask::SUBJECT_TYPES.keys)
    end
  end
end
