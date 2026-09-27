require "rails_helper"

# Epic #348, phase 7 — les notes datées d'une plante ou d'un objet de la carte.
RSpec.describe MapNote, type: :model do
  let(:layer) { MapLayer.for_kind(:management) }
  let(:feature) do
    layer.map_features.create!(feature_kind: "point", geometry: { "type" => "Point", "coordinates" => [4.9, 50.34] })
  end

  it "exige un texte et prend la date du jour par défaut" do
    expect(MapNote.new(subject: feature, body: "  ")).not_to be_valid
    note = MapNote.create!(subject: feature, body: "Bourgeons gelés")
    expect(note.noted_on).to eq(Date.current)
  end

  it "refuse un porteur hors de la liste fermée" do
    note = MapNote.new(body: "Intrus", subject_type: "User", subject_id: 1)
    expect(note).not_to be_valid
    expect(note.errors[:subject_type]).to be_present
  end

  it "se trie de la plus récente à la plus ancienne" do
    old = MapNote.create!(subject: feature, body: "Plantation", noted_on: Date.new(2025, 11, 20))
    recent = MapNote.create!(subject: feature, body: "Taille", noted_on: Date.new(2026, 3, 2))
    expect(MapNote.recent_first).to eq([recent, old])
  end
end
