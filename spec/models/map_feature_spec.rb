require "rails_helper"

# Epic #348, phase 2 — le modèle commun de tout ce qui se dessine sur la carte.
RSpec.describe MapFeature, type: :model do
  let(:layer) { MapLayer.for_kind(:management) }
  let(:ring) { [[4.905, 50.340], [4.906, 50.340], [4.906, 50.341], [4.905, 50.340]] }

  def feature(geometry, **attrs)
    MapFeature.new({ map_layer: layer, feature_kind: "zone", geometry: geometry }.merge(attrs))
  end

  describe "la géométrie" do
    it "accepte un Point, une LineString et un Polygon GeoJSON" do
      expect(feature({ "type" => "Point", "coordinates" => [4.9, 50.34] }, feature_kind: "point")).to be_valid
      expect(feature({ "type" => "LineString", "coordinates" => [[4.9, 50.34], [4.91, 50.341]] }, feature_kind: "path")).to be_valid
      expect(feature({ "type" => "Polygon", "coordinates" => [ring] })).to be_valid
    end

    it "accepte le GeoJSON en chaîne, comme l'envoie le champ caché" do
      f = feature({ "type" => "Point", "coordinates" => [4.9, 50.34] }.to_json, feature_kind: "point")
      expect(f).to be_valid
      expect(f.geometry).to eq("type" => "Point", "coordinates" => [4.9, 50.34])
    end

    it "refuse le reste" do
      [
        nil,
        {},
        "pas du json",
        { "type" => "MultiPolygon", "coordinates" => [[ring]] },
        { "type" => "Point", "coordinates" => [4.9] },
        { "type" => "Point", "coordinates" => [400, 50] },
        { "type" => "LineString", "coordinates" => [[4.9, 50.34]] },
        { "type" => "Polygon", "coordinates" => [ring[0..2]] },
        { "type" => "Polygon", "coordinates" => [ring[0..2] + [[4.0, 50.0]]] }
      ].each do |geometry|
        expect(feature(geometry)).not_to be_valid, "#{geometry.inspect} aurait dû être refusé"
      end
    end
  end

  describe "le nom et la description" do
    it "se replient sur le français" do
      f = feature({ "type" => "Point", "coordinates" => [4.9, 50.34] },
                  name_i18n: { "fr" => "Le verger", "nl" => "De boomgaard" },
                  description_i18n: { "fr" => "Pommiers" })
      expect(f.name(:nl)).to eq("De boomgaard")
      expect(f.name(:en)).to eq("Le verger")
      expect(f.description(:nl)).to eq("Pommiers")
    end
  end

  it "déduit le type d'objet de la géométrie" do
    expect(MapFeature.kind_for_geometry("type" => "Polygon")).to eq("zone")
    expect(MapFeature.kind_for_geometry("type" => "LineString")).to eq("path")
    expect(MapFeature.kind_for_geometry("type" => "Point")).to eq("point")
  end

  it "refuse une pièce jointe qui n'est pas une photo" do
    f = feature({ "type" => "Point", "coordinates" => [4.9, 50.34] }, feature_kind: "point")
    f.photos.attach(io: StringIO.new("%PDF-1.4"), filename: "plan.pdf", content_type: "application/pdf")
    expect(f).not_to be_valid
    expect(f.errors[:photos].join).to include("plan.pdf")
  end
end

RSpec.describe MapLayer, type: :model do
  it "crée la couche unique d'un type à la demande, une seule fois" do
    first = MapLayer.for_kind(:management)
    expect(MapLayer.for_kind("management")).to eq(first)
    expect(first.name).to eq("Gestion")
    expect(MapLayer.where(kind: "management").count).to eq(1)
  end

  it "refuse une seconde couche pour un type unique, pas pour un réseau" do
    MapLayer.for_kind(:management)
    expect(MapLayer.new(kind: "management", name: "Bis")).not_to be_valid

    MapLayer.create!(kind: "network", name: "Eau")
    expect(MapLayer.new(kind: "network", name: "Électricité")).to be_valid
  end

  it "garantit en base une seule couche vivante par type unique" do
    MapLayer.for_kind(:management)
    duplicate = MapLayer.new(kind: "management", name: "Gestion bis")
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(MapLayer.for_kind(:management)).to be_persisted
  end

  it "refuse un type inconnu" do
    expect { MapLayer.for_kind(:inconnu) }.to raise_error(ArgumentError)
    expect { MapLayer.for_kind(:network) }.to raise_error(ArgumentError)
  end
end

RSpec.describe MapFeature, ".photo_source" do
  it "sert l'original quand libvips manque, la variante sinon" do
    feature = MapFeature.new
    feature.photos.attach(io: StringIO.new("x"), filename: "a.png", content_type: "image/png")
    photo = feature.photos.first

    allow(MapFeature).to receive(:image_variants?).and_return(false)
    expect(MapFeature.photo_source(photo, :thumb)).to eq(photo)

    allow(MapFeature).to receive(:image_variants?).and_return(true)
    expect(MapFeature.photo_source(photo, :thumb)).to be_a(ActiveStorage::VariantWithRecord)
  end
end

RSpec.describe MapFeature, "photos HEIC" do
  let(:layer) { MapLayer.for_kind(:management) }
  let(:point) { { "type" => "Point", "coordinates" => [4.905, 50.340] } }

  def feature_with(content_type, filename)
    feature = layer.map_features.new(feature_kind: "point", geometry: point)
    feature.photos.attach(io: StringIO.new("x"), filename: filename, content_type: content_type)
    feature
  end

  it "refuse un HEIC avec un message clair quand le serveur ne sait pas le convertir" do
    allow(MapFeature).to receive(:heic_supported?).and_return(false)
    feature = feature_with("image/heic", "IMG_0001.HEIC")
    expect(feature).not_to be_valid
    expect(feature.errors[:photos].join).to include("IMG_0001.HEIC", "HEIC", "JPEG")
  end

  it "accepte un HEIC quand libvips sait le décoder" do
    allow(MapFeature).to receive(:heic_supported?).and_return(true)
    expect(feature_with("image/heic", "IMG_0001.HEIC")).to be_valid
  end

  it "accepte toujours le JPEG" do
    allow(MapFeature).to receive(:heic_supported?).and_return(false)
    expect(feature_with("image/jpeg", "photo.jpg")).to be_valid
  end
end
