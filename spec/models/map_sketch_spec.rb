require "rails_helper"

# Epic #348, phase 12 — les notes manuscrites dessinées sur la carte.
RSpec.describe MapSketch, type: :model do
  let(:alice) { User.create!(email: "alice-dessin@les4sources.be", password: "password123") }

  def stroke(points = [[50.3414, 4.9078], [50.3415, 4.9079]], id: "a1", width: 3)
    { "id" => id, "points" => points, "width" => width }
  end

  it "exige un nom, nettoyé des espaces ; le dossier vide devient nul" do
    sketch = MapSketch.create!(name: "  Idées potager  ", folder: "  ", created_by: alice)
    expect(sketch.name).to eq("Idées potager")
    expect(sketch.folder).to be_nil
    expect(sketch.strokes).to eq([])
    expect(MapSketch.new(name: " ")).not_to be_valid
  end

  it "accepte des tracés bien formés" do
    sketch = MapSketch.new(name: "Clôture", strokes: [stroke, stroke(id: "b2", width: 6)])
    expect(sketch).to be_valid
    expect(sketch.strokes_count).to eq(2)
  end

  it "refuse des tracés qui ne sont pas un tableau de tracés" do
    expect(MapSketch.new(name: "x", strokes: { "points" => [] })).not_to be_valid
    expect(MapSketch.new(name: "x", strokes: ["tracé"])).not_to be_valid
    expect(MapSketch.new(name: "x", strokes: [{ "id" => "a" }])).not_to be_valid
    expect(MapSketch.new(name: "x", strokes: [stroke([])])).not_to be_valid
  end

  it "refuse un point non numérique ou hors des bornes" do
    expect(MapSketch.new(name: "x", strokes: [stroke([["50.3", 4.9]])])).not_to be_valid
    expect(MapSketch.new(name: "x", strokes: [stroke([[91, 4.9]])])).not_to be_valid
    expect(MapSketch.new(name: "x", strokes: [stroke([[50.3, 181]])])).not_to be_valid
    expect(MapSketch.new(name: "x", strokes: [stroke([[50.3, 4.9, 12]])])).not_to be_valid
  end

  it "refuse une épaisseur absurde et un identifiant illisible" do
    expect(MapSketch.new(name: "x", strokes: [stroke(width: 0)])).not_to be_valid
    expect(MapSketch.new(name: "x", strokes: [stroke(width: 99)])).not_to be_valid
    expect(MapSketch.new(name: "x", strokes: [stroke(id: "<script>")])).not_to be_valid
  end

  it "plafonne les points par tracé et les tracés par dessin" do
    long = Array.new(MapSketch::MAX_POINTS + 1) { |i| [50.34, 4.9 + i * 1e-7] }
    expect(MapSketch.new(name: "x", strokes: [stroke(long)])).not_to be_valid

    many = Array.new(MapSketch::MAX_STROKES + 1) { |i| stroke(id: "s#{i}") }
    sketch = MapSketch.new(name: "x", strokes: many)
    expect(sketch).not_to be_valid
    expect(sketch.errors[:strokes].join).to include(MapSketch::MAX_STROKES.to_s)
  end

  it "range les dessins par dossier (sans dossier en tête), puis par nom" do
    b = MapSketch.create!(name: "Bêta", folder: "Potager")
    a = MapSketch.create!(name: "alpha", folder: "Potager")
    loose = MapSketch.create!(name: "Zèbre")
    other = MapSketch.create!(name: "Mare", folder: "Eau")
    expect(MapSketch.ordered.to_a).to eq([loose, other, a, b])
  end

  it "se supprime en douceur" do
    sketch = MapSketch.create!(name: "À jeter")
    sketch.soft_delete!
    expect(MapSketch.find_by(id: sketch.id)).to be_nil
    expect(MapSketch.with_deleted { MapSketch.find(sketch.id) }.deleted_at).to be_present
  end

  it "refuse d'écraser un dessin modifié ailleurs (verrou optimiste)" do
    sketch = MapSketch.create!(name: "Partagé")
    stale = MapSketch.find(sketch.id)
    sketch.update!(strokes: [stroke])
    stale.strokes = [stroke(id: "zz")]
    expect { stale.save! }.to raise_error(ActiveRecord::StaleObjectError)
  end
end
