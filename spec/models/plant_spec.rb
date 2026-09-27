require "rails_helper"

# Epic #348, phase 7 — les plantes nourricières : dossier, héritage des
# fenêtres de récolte, placement sur la carte.
RSpec.describe Plant, type: :model do
  let(:apple) { PlantSpecies.create!(name: "Pommier", latin_name: "Malus domestica") }
  let(:pear) { PlantSpecies.create!(name: "Poirier") }
  let(:reinette) { apple.varieties.create!(name: "Reinette Hernaut") }

  def plant(**attrs) = Plant.new({ name: "Pommier du verger" }.merge(attrs))

  describe "validations" do
    it "est à placer par défaut" do
      p = plant.tap(&:save!)
      expect(p.status).to eq("to_place")
      expect(p.status_label).to eq("À placer")
      expect(p).not_to be_placed
    end

    it "refuse les valeurs hors des listes fermées, accepte les vides" do
      { status: "gone", health: "meh", production: "lots", habit: "tall", stratum: "root",
        population: "few", stock_type: "pot" }.each do |attribute, value|
        expect(plant(attribute => value)).not_to be_valid, "#{attribute} = #{value} devrait être refusé"
      end
      expect(plant(health: "", production: nil, stratum: "")).to be_valid
    end

    it "a des libellés français collés à la base Notion" do
      p = plant(status: "wild", health: "worrying", production: "none", habit: "half_standard",
                stratum: "food_pollard", population: "single", stock_type: "forest_plug")
      expect([p.status_label, p.health_label, p.production_label, p.habit_label,
              p.stratum_label, p.population_label, p.stock_type_label])
        .to eq(["Flore sauvage", "Inquiétante", "Ne produit pas", "Moyenne tige",
                "Trogne alimentaire", "Un seul individu", "Mini-motte forestière"])
      expect(Plant::STATUSES["on_plan"]).to eq("Sur plan")
      expect(Plant::STRATA.keys).to include("coppice", "pollard", "espalier")
      expect(Plant::STRATA.keys).not_to include("root")
    end

    it "tient le numéro Notion unique parmi les plantes vivantes" do
      first = plant(number: 42).tap(&:save!)
      expect(plant(number: 42)).not_to be_valid
      expect(plant(number: nil)).to be_valid
      first.soft_delete!(validate: false)
      expect(plant(number: 42)).to be_valid
    end

    # La base Notion numérote « 9.1 », « 18.1 » les arbres ajoutés entre deux.
    it "accepte un numéro décimal et l'affiche tel qu'on l'écrit" do
      intercalated = plant(number: "9.1").tap(&:save!)
      whole = plant(number: 12).tap(&:save!)
      expect(intercalated.reload.number_label).to eq("9.1")
      expect(whole.reload.number_label).to eq("12")
      expect(Plant.ordered.where(id: [intercalated.id, whole.id])).to eq([intercalated, whole])
      expect(Plant.search("9.1")).to contain_exactly(intercalated)
      expect(plant(number: 0)).not_to be_valid
    end

    it "déduit l'espèce de la variété et le nom de l'espèce et de la variété" do
      p = Plant.create!(plant_variety: reinette)
      expect(p.plant_species).to eq(apple)
      expect(p.name).to eq("Pommier Reinette Hernaut")
    end

    it "refuse une variété d'une autre espèce" do
      p = plant(plant_species: pear, plant_variety: reinette)
      expect(p).not_to be_valid
      expect(p.errors[:plant_variety].join).to include("Poirier")
    end

    it "exige un nom quand il n'y a ni espèce ni variété" do
      expect(Plant.new(name: " ")).not_to be_valid
    end

    it "déduit l'année de plantation de la date" do
      expect(plant(planted_on: Date.new(2019, 11, 25)).tap(&:valid?).planted_year).to eq(2019)
    end

    it "refuse une photo qui n'en est pas une" do
      p = plant
      p.photos.attach(io: StringIO.new("%PDF-1.4"), filename: "facture.pdf", content_type: "application/pdf")
      expect(p).not_to be_valid
      expect(p.errors[:photos].join).to include("facture.pdf")
    end
  end

  describe "fenêtres de récolte" do
    let!(:species_fruit) { apple.harvest_windows.create!(part: "fruit", months: [9, 10]) }
    let!(:species_flower) { apple.harvest_windows.create!(part: "flower", months: [4]) }

    it "hérite des fenêtres de l'espèce tant qu'elle n'en a pas en propre" do
      p = plant(plant_species: apple).tap(&:save!)
      expect(p.harvest_windows_effective).to eq([species_flower, species_fruit])
      expect(p).to be_harvest_windows_inherited
      expect(p.harvest_months).to eq([4, 9, 10])
    end

    it "n'hérite plus rien dès qu'elle a une fenêtre propre" do
      p = plant(plant_species: apple).tap(&:save!)
      own = p.harvest_windows.create!(part: "fruit", months: [8])
      p.reload
      expect(p.harvest_windows_effective).to eq([own])
      expect(p).not_to be_harvest_windows_inherited
      expect(p.harvest_months).to eq([8])
    end

    it "n'a rien à hériter sans espèce" do
      p = plant.tap(&:save!)
      expect(p.harvest_windows_effective).to eq([])
      expect(p).not_to be_harvest_windows_inherited
    end

    describe ".harvestable_in" do
      let!(:inheriting) { plant(name: "Hérite", plant_species: apple).tap(&:save!) }
      let!(:overriding) do
        plant(name: "Surcharge", plant_species: apple).tap(&:save!).tap { |p| p.harvest_windows.create!(part: "fruit", months: [8]) }
      end
      let!(:dead) { plant(name: "Morte", plant_species: apple, status: "dead").tap(&:save!) }
      let!(:bare) { plant(name: "Sans espèce").tap(&:save!) }

      it "tient compte de l'héritage d'espèce et écarte les plantes mortes" do
        expect(Plant.harvestable_in(9)).to contain_exactly(inheriting)
        expect(Plant.harvestable_in(8)).to contain_exactly(overriding)
        expect(Plant.harvestable_in(4)).to contain_exactly(inheriting)
        expect(Plant.harvestable_in(1)).to be_empty
      end

      it "filtre par partie et se combine aux autres portées" do
        expect(Plant.harvestable_in(4, part: "fruit")).to be_empty
        expect(Plant.harvestable_in(4, part: "flower")).to contain_exactly(inheriting)
        inheriting.update!(zone: "Verger")
        expect(Plant.in_zone("Verger").harvestable_in(9)).to eq([inheriting])
        expect(Plant.in_zone("Potager").harvestable_in(9)).to be_empty
      end

      it "n'hérite pas d'une espèce supprimée" do
        apple.soft_delete!(validate: false)
        expect(Plant.harvestable_in(9)).to be_empty
      end

      it ".harvest_calendar range les plantes vivantes par mois, avec la partie" do
        calendar = Plant.harvest_calendar
        expect(calendar.keys).to eq((1..12).to_a)
        expect(calendar[9]).to eq([[inheriting, species_fruit]])
        expect(calendar[8].map { |p, w| [p, w.part] }).to eq([[overriding, "fruit"]])
        expect(Plant.harvest_calendar(part: "flower")[9]).to be_empty
      end
    end
  end

  describe "#place! et #unplace!" do
    let(:p) { plant(number: 7).tap(&:save!) }

    it "crée un point de plante dans la couche Plantes et passe la plante à « existante »" do
      p.place!(latitude: 50.3401, longitude: 4.9052)

      feature = p.map_feature
      expect(p).to be_placed
      expect(p.status).to eq("existing")
      expect(feature.map_layer).to eq(MapLayer.for_kind(:plants))
      expect(feature.feature_kind).to eq("plant")
      expect(feature.geometry).to eq("type" => "Point", "coordinates" => [4.9052, 50.3401])
      expect(feature.display_name).to eq("Pommier du verger")
      expect([p.latitude, p.longitude]).to eq([50.3401, 4.9052])
      expect(feature.plant).to eq(p)
    end

    it "déplace le même point et garde un statut qui n'était pas « à placer »" do
      p.update!(status: "to_move")
      p.place!(latitude: 50.34, longitude: 4.90)
      feature_id = p.map_feature_id
      p.place!(latitude: 50.35, longitude: 4.91)

      expect(p.map_feature_id).to eq(feature_id)
      expect(p.reload.longitude).to eq(4.91)
      expect(p.status).to eq("to_move")
    end

    it "refuse des coordonnées illisibles sans rien écrire" do
      expect { p.place!(latitude: "abc", longitude: 4.9) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(p.reload).not_to be_placed
      expect(MapFeature.where(feature_kind: "plant")).to be_empty
    end

    it "retire la plante de la carte : point supprimé, plante à placer" do
      p.place!(latitude: 50.34, longitude: 4.90)
      feature = p.map_feature
      p.unplace!

      expect(p.reload.map_feature_id).to be_nil
      expect(p.status).to eq("to_place")
      expect(MapFeature.find_by(id: feature.id)).to be_nil
      expect(Plant.to_place).to include(p)
    end

    it "redevient à placer quand son point est supprimé depuis la carte" do
      p.place!(latitude: 50.34, longitude: 4.90)
      p.map_feature.soft_delete!(validate: false)
      expect(p.reload.map_feature_id).to be_nil
      expect(p.status).to eq("to_place")
    end

    it "emporte son point quand elle est supprimée" do
      p.place!(latitude: 50.34, longitude: 4.90)
      feature_id = p.map_feature_id
      p.soft_delete!(validate: false)
      expect(MapFeature.find_by(id: feature_id)).to be_nil
    end

    it "renomme son point quand elle est renommée" do
      p.place!(latitude: 50.34, longitude: 4.90)
      p.update!(name: "Pommier cl")
      expect(p.map_feature.reload.name).to eq("Pommier cl")
    end

    it "refuse d'être liée à un objet de la carte qui n'est pas un point de plante" do
      zone = MapLayer.for_kind(:management).map_features.create!(
        feature_kind: "point", geometry: { "type" => "Point", "coordinates" => [4.9, 50.34] }
      )
      expect(plant(map_feature: zone)).not_to be_valid
    end
  end

  describe "portées" do
    let!(:verger) { plant(name: "Pommier cl", number: 12, zone: "Verger", plant_species: apple, plant_variety: reinette).tap(&:save!) }
    let!(:potager) { plant(name: "Rhubarbe", zone: "Potager", status: "dead").tap(&:save!) }

    it "filtre par zone, statut et vie" do
      expect(Plant.in_zone("Verger")).to eq([verger])
      expect(Plant.in_zone("")).to contain_exactly(verger, potager)
      expect(Plant.with_status("dead")).to eq([potager])
      expect(Plant.with_status(%w[dead to_place])).to contain_exactly(verger, potager)
      expect(Plant.with_status("bogus")).to contain_exactly(verger, potager)
      expect(Plant.alive).to eq([verger])
      expect(Plant.zones).to eq(%w[Potager Verger])
    end

    it "cherche par nom, numéro, espèce, nom latin et variété" do
      expect(Plant.search("rhub")).to eq([potager])
      expect(Plant.search("#12")).to eq([verger])
      expect(Plant.search("12")).to eq([verger])
      expect(Plant.search("malus")).to eq([verger])
      expect(Plant.search("hernaut")).to eq([verger])
      expect(Plant.search("")).to contain_exactly(verger, potager)
    end

    it "sépare les plantes placées et à placer" do
      verger.place!(latitude: 50.34, longitude: 4.90)
      expect(Plant.placed).to eq([verger])
      expect(Plant.to_place).to eq([potager])
    end
  end

  describe "tâches et notes" do
    let(:p) { plant.tap(&:save!) }

    it "porte des tâches de filière nourricier par défaut" do
      task = p.map_tasks.create!(label: "Taille de formation", months: [2])
      expect(task.sector).to eq("nourricier")
      expect(task.subject_name).to eq("Pommier du verger")
      expect(MapTask.with_live_subject).to eq([task])

      p.soft_delete!(validate: false)
      expect(MapTask.with_live_subject).to be_empty
    end

    it "liste ses notes de la plus récente à la plus ancienne" do
      old = p.map_notes.create!(body: "Plantée", noted_on: Date.new(2024, 11, 25))
      recent = p.map_notes.create!(body: "Chancre sur une branche", noted_on: Date.new(2026, 5, 3))
      expect(p.map_notes.reload).to eq([recent, old])
      expect(MapNote.with_live_subject).to contain_exactly(recent, old)

      p.soft_delete!(validate: false)
      expect(MapNote.with_live_subject).to be_empty
    end
  end
end
