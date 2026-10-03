require "rails_helper"

# L'import des observations d'observations.be dans la couche Biodiversité.
RSpec.describe Maps::ObservationsBeImport do
  let(:layer) { MapLayer.for_kind(:biodiversity) }

  def observation(id:, group: 1, name: "Bergeronnette grise", latin: "Motacilla alba", number: 2, notes: "")
    {
      "id" => id, "species_group" => group, "date" => "2026-05-07", "number" => number,
      "point" => { "type" => "Point", "coordinates" => [4.90769, 50.341339] }, "accuracy" => 10,
      "species_detail" => { "name" => name, "scientific_name" => latin, "group" => group },
      "user_detail" => { "name" => "François Hela" }, "permalink" => "https://observations.be/observation/#{id}/",
      "photos" => ["https://observations.be/media/photo/171587232.jpg", "https://observations.be/media/photo/171587233.jpg", "javascript:alert(1)"], "validation_status" => "J", "notes" => notes
    }
  end

  def import(pages)
    calls = []
    http = lambda do |url|
      calls << url
      pages.fetch(calls.size - 1)
    end
    [described_class.new(location_id: 241_623, layer: layer, http: http), calls]
  end

  it "crée un relevé par observation, avec la source, l'observateur et le lien d'origine" do
    importer, calls = import([
      { "results" => [observation(id: 1)], "next" => "https://observations.be/api/v1/locations/241623/observations/?offset=200" },
      { "results" => [observation(id: 2, group: 11, name: "Lépiote élevée", latin: "Macrolepiota procera", notes: "Sous les chênes")], "next" => nil }
    ])

    result = importer.call

    expect(result.created).to eq(2)
    expect(calls.first).to include("/locations/241623/observations/")
    bird = layer.map_features.find_by("properties->>'source_id' = '1'")
    expect(bird.properties).to include("realm" => "fauna", "species_common" => "Bergeronnette grise", "species_latin" => "Motacilla alba",
                                       "observed_on" => "2026-05-07", "count" => 2, "source" => "observations.be",
                                       "source_url" => "https://observations.be/observation/1/", "observer_name" => "François Hela",
                                       "photos_count" => 2,
                                       "photo_urls" => ["https://observations.be/media/photo/171587232.jpg",
                                                        "https://observations.be/media/photo/171587233.jpg"])
    expect(bird.feature_kind).to eq("observation")
    mushroom = layer.map_features.find_by("properties->>'source_id' = '2'")
    expect(mushroom.realm).to eq("fungi")
    expect(mushroom.description_i18n["fr"]).to eq("Sous les chênes")
  end

  it "met à jour au lieu de dupliquer quand on relance" do
    import([{ "results" => [observation(id: 7, number: 1)], "next" => nil }]).first.call
    result = import([{ "results" => [observation(id: 7, number: 5)], "next" => nil }]).first.call

    expect(result.updated).to eq(1)
    expect(result.created).to eq(0)
    expect(layer.map_features.where("properties->>'source_id' = '7'").count).to eq(1)
    expect(layer.map_features.find_by("properties->>'source_id' = '7'").observation_count).to eq(5)
  end

  it "classe plantes, mousses et algues en flore, et ignore les perturbations" do
    result = import([{ "results" => [observation(id: 3, group: 10, name: "Ail des ours"), observation(id: 4, group: 30, name: "Dépôt")], "next" => nil }]).first.call

    expect(result.created).to eq(1)
    expect(result.skipped).to eq(1)
    expect(layer.map_features.find_by("properties->>'source_id' = '3'").realm).to eq("flora")
  end

  it "ne touche pas aux relevés saisis dans Claudy" do
    own = layer.map_features.create!(feature_kind: "observation", geometry: { "type" => "Point", "coordinates" => [4.9, 50.34] },
                                     properties: { "realm" => "flora", "species_common" => "Ail des ours", "observed_on" => "2026-04-01" })

    import([{ "results" => [observation(id: 9)], "next" => nil }]).first.call

    expect(own.reload.properties).not_to have_key("source")
    expect(layer.map_features.count).to eq(2)
  end
end
