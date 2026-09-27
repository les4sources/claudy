require "rails_helper"

# Issue #370 — un tracé peut représenter plusieurs gîtes ou salles (la Chevêche
# et la Hulotte, superposées dans le même bâtiment) ; chaque gîte ou salle n'a
# toujours qu'un seul tracé vivant.
RSpec.describe MapFeature, "lieux représentés (issue #370)", type: :model do
  let(:venues) { MapLayer.for_kind(:venues) }
  let(:square) do
    { "type" => "Polygon",
      "coordinates" => [[[4.905, 50.340], [4.906, 50.340], [4.906, 50.341], [4.905, 50.340]]] }
  end
  let!(:cheveche) { Lodging.create!(name: "La Chevêche", price_night_cents: 42_000) }
  let!(:hulotte) { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }
  let!(:grande_salle) { Space.create!(name: "Grande Salle", capacity: 1) }

  def trace(*keys, **attrs)
    venues.map_features.new({ geometry: square, venue_keys: keys }.merge(attrs))
  end

  it "un tracé relié à deux gîtes est valide" do
    feature = trace("Lodging:#{hulotte.id}", "Lodging:#{cheveche.id}")
    expect(feature.save).to be(true)
    expect(feature.reload.venues).to eq([cheveche, hulotte])
    expect(feature.venue_names).to eq("La Chevêche · La Hulotte")
    expect(feature.display_name).to eq("La Chevêche · La Hulotte")
  end

  it "un nom propre l'emporte sur les noms des lieux" do
    feature = trace("Lodging:#{hulotte.id}", name_i18n: { "fr" => "Le bâtiment" })
    expect(feature.display_name).to eq("Le bâtiment")
  end

  it "refuse un gîte déjà relié à un autre tracé vivant, avec un message clair" do
    trace("Lodging:#{hulotte.id}").save!
    other = trace("Lodging:#{cheveche.id}", "Lodging:#{hulotte.id}")

    expect(other).not_to be_valid
    expect(other.errors.full_messages).to include("La Hulotte a déjà son tracé sur la carte")
  end

  it "la base refuse aussi le doublon" do
    feature = trace("Lodging:#{hulotte.id}").tap(&:save!)
    other = trace("Space:#{grande_salle.id}").tap(&:save!)
    expect {
      MapFeatureVenue.create!(map_feature: other, venue: hulotte)
    }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(feature.reload.venues).to eq([hulotte])
  end

  it "un tracé supprimé libère ses lieux pour un nouveau tracé" do
    feature = trace("Lodging:#{hulotte.id}", "Lodging:#{cheveche.id}").tap(&:save!)
    feature.soft_delete!(validate: false)

    expect(MapFeatureVenue.where(map_feature_id: feature.id)).to be_empty
    expect(trace("Lodging:#{hulotte.id}").save).to be(true)
  end

  it "un type hors liste ou un identifiant illisible est ignoré, jamais résolu" do
    feature = trace("User:1", "Kernel:2", "Lodging:abc", "Lodging:#{hulotte.id}")
    expect(feature.venue_keys).to eq(["Lodging:#{hulotte.id}"])
  end

  it "la liaison elle-même n'accepte qu'un gîte ou une salle" do
    feature = trace(feature_kind: "zone").tap(&:save!)
    link = MapFeatureVenue.new(map_feature: feature, venue_type: "User", venue_id: 1)
    expect(link).not_to be_valid
    expect(link.errors[:venue_type]).to be_present
  end

  describe "feature_kind dérivé" do
    it "lodging dès qu'un gîte est lié" do
      expect(trace("Space:#{grande_salle.id}", "Lodging:#{hulotte.id}").feature_kind).to eq("lodging")
    end

    it "space si seules des salles sont liées" do
      expect(trace("Space:#{grande_salle.id}").feature_kind).to eq("space")
    end

    it "retombe sur le type de la géométrie quand on délie tout" do
      feature = trace("Lodging:#{hulotte.id}").tap(&:save!)
      feature.venue_keys = [""]
      feature.save!
      expect(feature.reload.feature_kind).to eq("zone")
      expect(feature.venues).to be_empty
    end
  end

  it "modifier les cases ajoute et retire les bonnes liaisons" do
    feature = trace("Lodging:#{hulotte.id}").tap(&:save!)
    kept_link = feature.map_feature_venues.first

    feature.venue_keys = ["Lodging:#{hulotte.id}", "Lodging:#{cheveche.id}"]
    feature.save!
    expect(feature.reload.venue_keys).to contain_exactly("Lodging:#{hulotte.id}", "Lodging:#{cheveche.id}")
    expect(feature.map_feature_venues).to include(kept_link)

    feature.venue_keys = ["Lodging:#{cheveche.id}"]
    feature.save!
    expect(feature.reload.venues).to eq([cheveche])
  end
end
