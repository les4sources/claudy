require "rails_helper"

# Epic #348, phase 6 — la consigne de gestion devient un plan de travail mois
# par mois : une tâche porte sur un objet de la carte et revient certains mois.
RSpec.describe MapTask, type: :model do
  let(:layer) { MapLayer.for_kind(:management) }
  let(:ring) { [[4.905, 50.340], [4.906, 50.340], [4.906, 50.341], [4.905, 50.340]] }
  let(:feature) do
    layer.map_features.create!(feature_kind: "zone", geometry: { "type" => "Polygon", "coordinates" => [ring] },
                               name_i18n: { "fr" => "La prairie" })
  end

  def task(**attrs)
    feature.map_tasks.new({ label: "Fauche des orties", months: [6] }.merge(attrs))
  end

  it "est valide avec un libellé, des mois et un porteur" do
    expect(task).to be_valid
  end

  it "exige un libellé" do
    expect(task(label: "  ")).not_to be_valid
  end

  it "prend la filière terrain par défaut pour un objet de la carte, modifiable" do
    expect(task.tap(&:valid?).sector).to eq("terrain")
    expect(task(sector: "nourricier").tap(&:valid?).sector).to eq("nourricier")
  end

  it "refuse une filière inconnue" do
    expect(task(sector: "potager")).not_to be_valid
  end

  it "déduplique et trie les mois, et ignore les cases vides du formulaire" do
    t = task(months: ["10", "", "3", "10"])
    expect(t).to be_valid
    expect(t.months).to eq([3, 10])
  end

  it "refuse un mois hors de 1 à 12" do
    expect(task(months: [0])).not_to be_valid
    expect(task(months: [13])).not_to be_valid
  end

  it "accepte une tâche sans mois (fréquence libre seulement)" do
    expect(task(months: [], frequency: "tous les 2 ans")).to be_valid
  end

  it "refuse un porteur hors de la liste fermée" do
    t = MapTask.new(label: "Intrus", subject_type: "User", subject_id: 1)
    expect(t).not_to be_valid
    expect(t.errors[:subject_type]).to be_present
  end

  it "numérote les tâches d'un même porteur dans l'ordre de création" do
    first = task.tap(&:save!)
    second = task(label: "Taille").tap(&:save!)
    expect(second.position).to eq(first.position + 1)
    expect(feature.map_tasks.ordered).to eq([first, second])
  end

  it "est soft-deletée et versionnée" do
    t = task.tap(&:save!)
    t.soft_delete!
    expect(MapTask.find_by(id: t.id)).to be_nil
    expect(MapTask.unscoped.find(t.id).deleted_at).to be_present
    expect(t.versions).to be_present
  end

  describe ".in_month et .with_live_subject" do
    it "trouve une tâche dans chacun de ses mois et écarte celles d'un objet supprimé" do
      march_october = task(months: [3, 10]).tap(&:save!)
      other = layer.map_features.create!(feature_kind: "point", geometry: { "type" => "Point", "coordinates" => [4.9, 50.34] })
      orphan = other.map_tasks.create!(label: "Orpheline", months: [3])
      other.soft_delete!(validate: false)

      expect(MapTask.in_month(3).with_live_subject).to eq([march_october])
      expect(MapTask.in_month(10)).to eq([march_october])
      expect(MapTask.in_month(4)).to be_empty
      expect(MapTask.in_month(3)).to include(orphan)
    end
  end
end
