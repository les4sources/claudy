require "rails_helper"

# Les relevés de plantes bio-indicatrices et les fiches espèces : statut,
# analyse validée, filtres de la liste, fiche réutilisable.
RSpec.describe MapFeatureBioindicator do
  include ActiveSupport::Testing::TimeHelpers

  let(:layer) { MapLayer.for_kind(:bioindicators) }
  let(:renoncule) do
    BioindicatorSpecies.create!(latin_name: "Ranunculus repens", name: "Renoncule rampante", family: "Ranunculaceae",
                                agronomy: "degrading", indicators: [{ key: "waterlogging", strength: 3 }, { key: "compaction", strength: 2 }])
  end

  def record!(properties = {})
    layer.map_features.create!(feature_kind: "bioindicator", geometry: { "type" => "Point", "coordinates" => [4.9078, 50.3414] },
                               properties: properties)
  end

  def analysis(overrides = {})
    { "summary" => "Sol frais à engorgement hivernal, tassé par le piétinement.", "agronomy" => "degrading",
      "indicators" => [{ "key" => "waterlogging", "strength" => 2 }, { "key" => "compaction", "strength" => 2 }],
      "species" => [{ "species_id" => renoncule.id, "name" => "Renoncule rampante", "latin_name" => "Ranunculus repens",
                      "confidence" => "high", "abundance" => "frequent" }] }.merge(overrides)
  end

  it "naît « À analyser », daté du jour" do
    travel_to Time.zone.local(2026, 10, 2, 9) do
      feature = record!
      expect(feature.properties).to include("status" => "to_analyze", "observed_on" => "2026-10-02")
      expect(feature.bioindicator_title).to eq("Relevé du 2 octobre 2026")
      expect(feature.as_geojson[:properties]).to include(status: "to_analyze", feature_kind: "bioindicator")
    end
  end

  it "porte son analyse : diagnostic, état agronomique, indicateurs et espèces vues" do
    feature = record!("status" => "analyzed", "analysis" => analysis)

    expect(feature.analysis_agronomy).to eq("degrading")
    expect(feature.analysis_indicators.map { |item| item[:label] }).to eq(["Engorgement, hydromorphie", "Tassement, asphyxie"])
    expect(feature.analysis_species_sheets.keys).to eq([renoncule.id])
    expect(feature.bioindicator_title).to eq("Renoncule rampante")
    expect(feature.display_name).to eq("Renoncule rampante")
    expect(feature.as_geojson[:properties]).to include(agronomy: "degrading", indicators: %w[waterlogging compaction])
  end

  it "refuse une analyse mal formée" do
    feature = layer.map_features.new(feature_kind: "bioindicator", geometry: { "type" => "Point", "coordinates" => [4.9, 50.34] })

    feature.properties = { "status" => "analyzed" }
    expect(feature).not_to be_valid
    expect(feature.errors.full_messages).to include("Un relevé analysé porte son analyse.")

    feature.properties = { "status" => "analyzed", "analysis" => analysis("summary" => "", "agronomy" => "superbe",
                                                                         "indicators" => [{ "key" => "lune", "strength" => 5 }]) }
    expect(feature).not_to be_valid
    expect(feature.errors.full_messages).to include("L'analyse porte un diagnostic (summary).", "État agronomique inconnu : superbe.",
                                                    "Indicateur inconnu : lune.", "La force d'un indicateur va de 1 à 3.")

    feature.properties = { "status" => "analyzed", "analysis" => analysis("species" => [{ "species_id" => 999_999, "name" => "X" }]) }
    expect(feature).not_to be_valid
    expect(feature.errors.full_messages).to include("Fiche espèce inconnue : 999999.")
  end

  it "redemande une analyse sans perdre la précédente" do
    feature = record!("status" => "analyzed", "analysis" => analysis)
    feature.request_bioindicator_analysis!

    expect(feature.reload.bioindicator_status).to eq("to_analyze")
    expect(feature.analysis["summary"]).to start_with("Sol frais")
  end

  it "filtre la liste par statut et par indicateur" do
    pending_one = record!
    wet = record!("status" => "analyzed", "analysis" => analysis)
    dry = record!("status" => "analyzed", "analysis" => analysis("indicators" => [{ "key" => "drought", "strength" => 2 }]))

    expect(MapFeature.filter_bioindicators(status: "to_analyze")).to eq([pending_one])
    expect(MapFeature.filter_bioindicators(indicator: "waterlogging")).to eq([wet])
    expect(MapFeature.filter_bioindicators(indicator: "drought")).to eq([dry])
    expect(MapFeature.filter_bioindicators(indicator: "inconnu").count).to eq(3)
  end

  describe BioindicatorSpecies do
    it "garde une fiche par nom latin, casse ignorée" do
      renoncule
      duplicate = BioindicatorSpecies.new(latin_name: "ranunculus REPENS", name: "Autre")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors.full_messages.join).to include("a déjà sa fiche")
    end

    it "range ses indicateurs (une clé, la plus forte) et refuse l'inconnu" do
      sheet = BioindicatorSpecies.create!(latin_name: "Achillea millefolium", name: "Achillée millefeuille",
                                          indicators: [{ "key" => "erosion", "strength" => "1" }, { "key" => "erosion", "strength" => 3 }])
      expect(sheet.indicators).to eq([{ "key" => "erosion", "strength" => 3 }])
      expect(sheet.indicator_list).to eq([{ key: "erosion", label: "Érosion, sol mis à nu", strength: 3 }])

      sheet.indicators = [{ "key" => "magie", "strength" => 1 }]
      expect(sheet).not_to be_valid
      expect(sheet.errors.full_messages).to include("Indicateur inconnu : magie.")
    end
  end
end
