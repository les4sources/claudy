require "rails_helper"
require Rails.root.join("db/migrate/20260927010000_create_map_feature_venues.rb")

# Issue #370 — la reprise des liens uniques `linked_type`/`linked_id` dans la
# table de liaison. Les colonnes étant ignorées par le modèle, on les écrit en
# SQL, comme les a laissées la phase 3.
RSpec.describe CreateMapFeatureVenues do
  let(:venues) { MapLayer.for_kind(:venues) }
  let(:square) do
    { "type" => "Polygon",
      "coordinates" => [[[4.905, 50.340], [4.906, 50.340], [4.906, 50.341], [4.905, 50.340]]] }
  end
  let!(:hulotte) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }

  def legacy_feature(type, id, deleted: false)
    feature = venues.map_features.create!(geometry: square, feature_kind: type.downcase)
    sql = MapFeature.sanitize_sql_array(["UPDATE map_features SET linked_type = ?, linked_id = ? WHERE id = ?", type, id, feature.id])
    MapFeature.connection.execute(sql)
    feature.soft_delete!(validate: false) if deleted
    feature
  end

  def migration = described_class.new.tap { |m| m.verbose = false }

  it "donne à chaque tracé relié une liaison identique" do
    lodging_feature = legacy_feature("Lodging", hulotte.id)
    space_feature = legacy_feature("Space", grande_salle.id)

    migration.backfill_from_linked

    expect(MapFeatureVenue.pluck(:map_feature_id, :venue_type, :venue_id)).to contain_exactly(
      [lodging_feature.id, "Lodging", hulotte.id], [space_feature.id, "Space", grande_salle.id]
    )
  end

  it "ignore les tracés supprimés et se rejoue sans doublon" do
    legacy_feature("Lodging", hulotte.id, deleted: true)
    live = legacy_feature("Space", grande_salle.id)

    2.times { migration.backfill_from_linked }

    expect(MapFeatureVenue.pluck(:map_feature_id)).to eq([live.id])
  end

  it "au retour arrière, chaque tracé reprend son premier lieu dans linked_*" do
    feature = venues.map_features.create!(geometry: square, venue_keys: ["Lodging:#{hulotte.id}"])

    migration.restore_linked

    row = MapFeature.connection.select_one("SELECT linked_type, linked_id FROM map_features WHERE id = #{feature.id}")
    expect(row).to eq("linked_type" => "Lodging", "linked_id" => hulotte.id)
  end
end
