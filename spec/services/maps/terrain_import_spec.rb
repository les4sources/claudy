require "rails_helper"

# Le relief de la vue 3D : le MNT LiDAR du SPW lu par `identify` en multipoint,
# une altitude par point, dans l'ordre des points. Un faux SPW répond ici une
# altitude calculée à partir des coordonnées : on peut ainsi vérifier que
# chaque valeur retombe dans la bonne maille de la grille.
RSpec.describe Maps::TerrainImport do
  let(:bounds) { { "south" => 50.3392832, "west" => 4.9031066, "north" => 50.3435344, "east" => 4.9126003 } }
  let(:root) { Pathname(Dir.mktmpdir("map-terrain")) }
  let(:terrain) { Maps::Terrain.new(root: root) }
  let(:calls) { [] }

  after { FileUtils.rm_rf(root) }

  def height_at(x, y)
    120.0 + (x - 545_000) / 100.0 + (y - 6_506_000) / 1000.0
  end

  def fake_spw(drop_last: false, nodata_every: nil)
    lambda do |url, params|
      calls << url
      if url.end_with?("/export")
        "\xFF\xD8\xFF\xE0fake-jpeg".b
      else
        points = JSON.parse(params[:geometry])["points"]
        points = points[0...-1] if drop_last
        results = points.each_with_index.map do |(x, y), i|
          # La surface (MNS) dépasse le terrain de 5 m partout : des arbres.
          lift = url.include?("WALLONIE_MNS") ? 5 : 0
          value = nodata_every && (i % nodata_every).zero? ? "NoData" : format("%.6f", height_at(x, y) + lift)
          # L'occupation du sol : prairie à l'ouest, feuillus à l'est.
          value = (x < 546_300 ? "7" : "9") if url.include?("WAL_OCS")
          { "layerId" => 0, "attributes" => { "Stretch.Pixel Value" => value } }
        end
        { results: results }.to_json
      end
    end
  end

  def importer(**options)
    described_class.new(bounds: bounds, terrain: terrain, http: fake_spw(**options), cell_size_m: 10.0,
                        margin_m: 20.0, chunk: 500)
  end

  it "pose une grille métrique en Mercator, marge comprise" do
    extent = described_class.extent_for(bounds)

    # 1 m au sol vaut 1/cos(50,34°) ≈ 1,567 unité de Mercator.
    expect(extent.step).to be_within(0.001).of(1.5669)
    # ~675 m d'est en ouest + 2 × 150 m de marge, à 1 m.
    expect(extent.cols).to be_between(970, 980)
    expect(extent.rows).to be_between(770, 780)
  end

  it "range chaque altitude dans sa maille, du nord au sud et d'ouest en est" do
    import = importer
    import.call(texture: false)

    meta = terrain.metadata
    values = File.binread(terrain.grid_path).unpack("v*")
    expect(values.size).to eq(meta["cols"] * meta["rows"])
    expect(calls.size).to be > 1

    [0, meta["cols"] - 1, meta["cols"] * 3 + 7, values.size - 1].each do |index|
      x, y = import.extent.point(index)
      decoded = meta["z_min"] + values[index] * meta["z_unit"]
      expect(decoded).to be_within(0.006).of(height_at(x, y))
    end
    expect(meta).to include("crs" => "EPSG:3857", "cell_size_m" => 10.0, "nodata_count" => 0)
    expect(terrain).to be_installed
  end

  it "marque « sans donnée » les points que le SPW ne connaît pas" do
    importer(nodata_every: 7).call(texture: false)

    values = File.binread(terrain.grid_path).unpack("v*")
    expect(values.count(Maps::Terrain::NODATA)).to eq(terrain.metadata["nodata_count"])
    expect(terrain.metadata["nodata_count"]).to be > 0
  end

  # Un paquet incomplet décalerait toute la grille : on préfère échouer.
  it "refuse un paquet où il manque des altitudes" do
    stub_const("#{described_class}::ATTEMPTS", 1)

    expect { importer(drop_last: true).call(texture: false) }.to raise_error(described_class::Error, /altitudes pour/)
    expect(terrain).not_to be_installed
  end

  it "pose la surface (arbres et toits) sur la même grille, avec son propre minimum" do
    importer.call(texture: false)

    meta = terrain.metadata
    expect(terrain).to be_surface
    expect(meta["surface"]).to include("z_unit" => 0.01, "nodata_count" => 0)
    ground = File.binread(terrain.grid_path).unpack("v*")
    surface = File.binread(terrain.surface_path).unpack("v*")
    index = meta["cols"] * 2 + 3
    above = (meta["surface"]["z_min"] + surface[index] * 0.01) - (meta["z_min"] + ground[index] * 0.01)
    expect(above).to be_within(0.02).of(5)
  end

  it "n'ajoute la surface seule qu'à un relief de même emprise" do
    expect { importer.call(terrain: false, texture: false) }.to raise_error(described_class::Error, /relief/)

    importer.call(surface: false, texture: false)
    expect(terrain).not_to be_surface
    importer.call(terrain: false, texture: false)
    expect(terrain).to be_surface
  end

  it "pose l'occupation du sol sur la même grille, un octet par maille" do
    import = importer
    import.call(texture: false)

    classes = File.binread(terrain.landcover_path).unpack("C*")
    meta = terrain.metadata
    expect(classes.size).to eq(meta["cols"] * meta["rows"])
    x, = import.extent.point(0)
    expect(classes.first).to eq(x < 546_300 ? 7 : 9)
    expect(classes.uniq.sort).to eq([7, 9])
    expect(meta["landcover"]["classes"]).to include("7" => "Prairie permanente", "9" => "Feuillus (> 3 m)")
    expect(terrain).to be_landcover
  end

  it "télécharge l'ortho sur la même emprise et le note dans les métadonnées" do
    importer.call

    expect(terrain).to be_texture
    expect(terrain.metadata["texture"]).to include("source" => "SPW, ortho printemps 2026")
    expect(calls.last).to end_with("/export")
  end
end
