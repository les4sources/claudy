require "rails_helper"

# Epic #348, phase 13 — un relevé de biodiversité : un point `observation` de la
# couche Biodiversité, dont les `properties` disent le règne, l'espèce, la date,
# l'observateur et l'effectif.
RSpec.describe MapFeatureObservation, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:layer) { MapLayer.for_kind(:biodiversity) }
  let(:alice) { User.create!(email: "alice-releve@les4sources.be", password: "password123") }
  let(:bob) { User.create!(email: "bob-releve@les4sources.be", password: "password123") }
  let(:point) { { "type" => "Point", "coordinates" => [4.9078, 50.3414] } }

  def observation(properties = {}, attrs = {})
    MapFeature.new({ map_layer: layer, feature_kind: "observation", geometry: point, created_by: alice,
                     properties: { "realm" => "flora", "species_common" => "Ail des ours" }.merge(properties) }.merge(attrs))
  end

  it "accepte un relevé complet" do
    record = observation("species_latin" => "Allium ursinum", "observed_on" => "2026-04-12",
                         "observer_id" => bob.id, "count" => "12")
    expect(record).to be_valid
    expect(record.realm).to eq("flora")
    expect(record.realm_label).to eq("Flore")
    expect(record.species_latin).to eq("Allium ursinum")
    expect(record.observed_on).to eq(Date.new(2026, 4, 12))
    expect(record.observer).to eq(bob)
    expect(record.observation_count).to eq(12)
  end

  it "exige le règne, parmi flore et faune" do
    expect(observation("realm" => nil)).not_to be_valid
    expect(observation("realm" => "fungi")).not_to be_valid
    expect(observation("realm" => "fauna")).to be_valid
  end

  it "exige le nom commun de l'espèce, sans espaces parasites" do
    expect(observation("species_common" => "  ")).not_to be_valid
    record = observation("species_common" => "  Hérisson  ", "realm" => "fauna")
    expect(record).to be_valid
    expect(record.species_common).to eq("Hérisson")
  end

  it "date le relevé d'aujourd'hui et l'attribue à son auteur par défaut" do
    travel_to Time.zone.local(2026, 9, 28, 10) do
      record = observation
      expect(record).to be_valid
      expect(record.properties["observed_on"]).to eq("2026-09-28")
      expect(record.observer).to eq(alice)
    end
  end

  it "refuse une date illisible ou future" do
    travel_to Time.zone.local(2026, 9, 28, 10) do
      expect(observation("observed_on" => "hier")).not_to be_valid
      expect(observation("observed_on" => "2026-09-29")).not_to be_valid
    end
  end

  it "accepte un effectif vide, refuse zéro, un négatif ou un texte" do
    expect(observation("count" => "")).to be_valid
    expect(observation("count" => "").tap(&:valid?).properties).not_to have_key("count")
    %w[0 -3 beaucoup 2.5].each { |value| expect(observation("count" => value)).not_to be_valid, value }
  end

  it "refuse un observateur inconnu" do
    expect(observation("observer_id" => 0)).not_to be_valid
  end

  it "n'accepte qu'un point" do
    line = { "type" => "LineString", "coordinates" => [[4.9, 50.34], [4.91, 50.341]] }
    expect(observation({}, geometry: line)).not_to be_valid
  end

  it "ne touche pas aux autres objets de la carte" do
    zone = MapFeature.new(map_layer: MapLayer.for_kind(:management), feature_kind: "point", geometry: point)
    expect(zone).to be_valid
    expect(zone.properties.to_h).not_to have_key("observed_on")
  end

  it "prend l'espèce pour nom et expose le règne à la carte" do
    record = observation("species_common" => "Chevreuil", "realm" => "fauna")
    record.save!
    props = record.as_geojson[:properties]
    expect(props[:name]).to eq("Chevreuil")
    expect(props[:realm]).to eq("fauna")
  end

  describe "les requêtes du panneau" do
    before do
      observation("species_common" => "Ail des ours", "species_latin" => "Allium ursinum", "observed_on" => "2026-04-12").save!
      observation("species_common" => "ail des ours", "species_latin" => "Allium ursinum", "observed_on" => "2025-04-02").save!
      observation("species_common" => "Ail des ours", "species_latin" => "Allium ursinus", "observed_on" => "2026-05-01").save!
      observation("species_common" => "Chevreuil", "realm" => "fauna", "observed_on" => "2026-06-01").save!
      observation("species_common" => "Ailante", "observed_on" => "2024-06-01").save!
    end

    it "trie par date décroissante" do
      expect(MapFeature.observations_by_date.map(&:observed_on).map(&:to_s))
        .to eq(%w[2026-06-01 2026-05-01 2026-04-12 2025-04-02 2024-06-01])
    end

    it "filtre par règne, espèce (sans casse) et année" do
      expect(MapFeature.filter_observations(realm: "fauna").map(&:species_common)).to eq(["Chevreuil"])
      expect(MapFeature.filter_observations(species: "AIL DES OURS").count).to eq(3)
      expect(MapFeature.filter_observations(year: "2026").count).to eq(3)
      expect(MapFeature.filter_observations(realm: "flora", year: 2025).count).to eq(1)
      expect(MapFeature.filter_observations(realm: "rien", year: "abc").count).to eq(5)
    end

    it "compte les espèces distinctes, sans tenir compte de la casse" do
      expect(MapFeature.distinct_species_count(MapFeature.filter_observations)).to eq(3)
      expect(MapFeature.distinct_species_count(MapFeature.filter_observations(year: 2026))).to eq(2)
    end

    it "propose les espèces déjà saisies, avec le latin le plus fréquent" do
      suggestions = MapFeature.observation_species_suggestions("ail")
      expect(suggestions.first).to include(common: "Ail des ours", latin: "Allium ursinum", realm: "flora", count: 3)
      expect(suggestions.map { |s| s[:common] }).to eq(["Ail des ours", "Ailante"])
      expect(MapFeature.observation_species_suggestions("ail", realm: "fauna")).to be_empty
      expect(MapFeature.observation_species_suggestions("%")).to be_empty
    end

    it "ignore les relevés supprimés" do
      MapFeature.observations.find_by("properties->>'species_common' = ?", "Chevreuil").soft_delete!(validate: false)
      expect(MapFeature.distinct_species_count(MapFeature.filter_observations)).to eq(2)
    end
  end
end
