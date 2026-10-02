# Un relevé de plantes bio-indicatrices : un point `bioindicator` de la couche
# « Bio-indicatrices ». On s'arrête sur le terrain, on photographie les plantes
# (une ou plusieurs photos), on note au besoin ; le point naît « À analyser ».
# L'analyse vient ensuite, à la demande, par Claude (par l'API agent) : les
# espèces vues sur les photos, ce qu'elles disent du sol, et un diagnostic.
#
# Comme un relevé de biodiversité, pas de table à part : le relevé EST un
# `MapFeature` (géométrie, photos, soft-delete, PaperTrail), et ce qu'il a en
# propre vit dans ses `properties` :
#
# - `observed_on` : la date, ISO 8601 (aujourd'hui par défaut, jamais future) ;
# - `observer_id` : qui a photographié (l'auteur du point par défaut) ;
# - `status` : `to_analyze` ou `analyzed` ;
# - `analysis` : la dernière analyse (voir `ANALYSIS_KEYS`), gardée quand une
#   nouvelle est demandée, jusqu'à ce qu'elle soit remplacée.
#
# L'analyse : `analyzed_on`, `summary` (le diagnostic de sol, requis),
# `agronomy` (état agronomique d'ensemble), `indicators` (codés, avec leur
# force), `species` (chaque espèce vue : sa fiche `species_id`, son nom et son
# nom latin, la confiance de l'identification et son abondance sur les photos,
# une note), et au besoin `advice` (pistes de gestion) et `caution` (limites).
# Les notes de terrain sont la description de l'objet.
module MapFeatureBioindicator
  extend ActiveSupport::Concern

  BIOINDICATOR_STATUSES = { "to_analyze" => "À analyser", "analyzed" => "Analysé" }.freeze
  BIOINDICATOR_KEYS = %w[observed_on observer_id status analysis].freeze
  ANALYSIS_KEYS = %w[analyzed_on analyst summary agronomy indicators species advice caution].freeze
  CONFIDENCES = { "high" => "Sûre", "medium" => "Probable", "low" => "Incertaine" }.freeze
  ABUNDANCES = { "dominant" => "Dominante", "frequent" => "Fréquente", "present" => "Présente", "rare" => "Rare" }.freeze
  SUMMARY_MAX_LENGTH = 6000

  included do
    before_validation :normalize_bioindicator_properties, if: :bioindicator_point?
    validate :bioindicator_properties_are_valid, if: :bioindicator_point?

    scope :bioindicators, -> { where(feature_kind: "bioindicator") }
    scope :bioindicators_by_date, lambda {
      bioindicators.order(Arel.sql("properties->>'observed_on' DESC NULLS LAST"), id: :desc)
    }
  end

  class_methods do
    # Les relevés de la liste : un statut, un indicateur (« sol engorgé »). Un
    # filtre inconnu est ignoré.
    def filter_bioindicators(status: nil, indicator: nil)
      scope = bioindicators_by_date
      scope = scope.where("properties->>'status' = ?", status.to_s) if BIOINDICATOR_STATUSES.key?(status.to_s)
      if BioindicatorVocabulary::INDICATORS.key?(indicator.to_s)
        scope = scope.where("properties->'analysis'->'indicators' @> ?::jsonb", [{ key: indicator.to_s }].to_json)
      end
      scope
    end
  end

  def bioindicator_point? = feature_kind == "bioindicator"

  def bioindicator_status = properties.to_h["status"]
  def bioindicator_status_label = BIOINDICATOR_STATUSES[bioindicator_status]
  def to_analyze? = bioindicator_status == "to_analyze"
  def analysis = properties.to_h["analysis"].presence
  def analyzed? = analysis.present?
  def analysis_agronomy = analysis&.dig("agronomy")
  def analysis_species = Array(analysis&.dig("species"))

  # [{ key:, label:, strength: }], du plus fort au plus léger.
  def analysis_indicators
    Array(analysis&.dig("indicators")).sort_by { |item| -item["strength"].to_i }.map do |item|
      { key: item["key"], label: BioindicatorVocabulary::INDICATORS[item["key"]], strength: item["strength"].to_i }
    end
  end

  # Les fiches des espèces vues, par id.
  def analysis_species_sheets
    ids = analysis_species.filter_map { |species| species["species_id"] }
    BioindicatorSpecies.where(id: ids).index_by(&:id)
  end

  # Le nom d'un relevé sans nom : ses espèces une fois analysé, sinon sa date.
  def bioindicator_title
    # Les espèces qui ont une fiche d'abord : « Poacées indéterminées » ne dit rien.
    names = analysis_species.sort_by { |species| species["species_id"] ? 0 : 1 }.filter_map { |species| species["name"] }
    return names.first(3).join(", ") + (names.size > 3 ? "…" : "") if names.any?

    date = properties.to_h["observed_on"]
    date ? "Relevé du #{I18n.l(Date.iso8601(date), format: :long).squish}" : "Relevé"
  rescue Date::Error
    "Relevé"
  end

  # Les champs de la fiche : seules les clés d'un relevé passent, les autres
  # `properties` restent en place.
  def bioindicator_attributes=(attrs)
    attrs = attrs.to_h.stringify_keys.slice(*BIOINDICATOR_KEYS)
    self.properties = properties.to_h.merge(attrs)
  end

  # Redemander une analyse : la précédente reste lisible jusqu'à la suivante.
  def request_bioindicator_analysis!
    self.properties = properties.to_h.merge("status" => "to_analyze")
    save!
  end

  # Ce que la carte lit d'un relevé : le statut et la couleur (état du sol).
  def bioindicator_geojson_properties
    return {} unless bioindicator_point?

    { status: bioindicator_status, agronomy: analysis_agronomy, observed_on: properties.to_h["observed_on"],
      indicators: analysis_indicators.map { |item| item[:key] } }.compact
  end

  private

  def normalize_bioindicator_properties
    props = properties.to_h.dup
    props["observed_on"] = props["observed_on"].to_s.strip.presence || Date.current.iso8601
    props["observer_id"] = props["observer_id"].presence || created_by_id
    props["observer_id"] = Integer(props["observer_id"], exception: false) || props["observer_id"] if props["observer_id"]
    props["status"] = props["status"].to_s.strip.presence || "to_analyze"
    if props["analysis"].respond_to?(:to_h) && props["analysis"].present?
      analysis = props["analysis"].to_h.stringify_keys.slice(*ANALYSIS_KEYS)
      %w[summary advice caution analyst].each { |key| analysis[key] = analysis[key].to_s.strip.presence }
      analysis["analyzed_on"] = analysis["analyzed_on"].to_s.strip.presence || Date.current.iso8601
      analysis["indicators"] = BioindicatorVocabulary.normalize_indicators(analysis["indicators"] || [])
      analysis["species"] = Array(analysis["species"]).map do |species|
        species = species.respond_to?(:to_h) ? species.to_h.stringify_keys : species
        next species unless species.is_a?(Hash)

        species["species_id"] = Integer(species["species_id"].to_s, exception: false) || species["species_id"]
        species.transform_values { |value| value.is_a?(String) ? value.strip.presence : value }.compact
      end
      props["analysis"] = analysis.compact
    else
      props.delete("analysis")
    end
    self.properties = props.reject { |_, value| value.nil? || value == "" }
  end

  def bioindicator_properties_are_valid
    errors.add(:base, "Un relevé est un point de la carte.") unless geometry_type == "Point"
    date = begin
      Date.iso8601(properties.to_h["observed_on"].to_s)
    rescue Date::Error
      nil
    end
    if date.nil?
      errors.add(:base, "La date du relevé est illisible.")
    elsif date > Date.current
      errors.add(:base, "La date du relevé ne peut pas être dans le futur.")
    end
    errors.add(:base, "Statut inconnu.") unless BIOINDICATOR_STATUSES.key?(bioindicator_status)
    errors.add(:base, "Un relevé analysé porte son analyse.") if bioindicator_status == "analyzed" && !analyzed?
    analysis_errors.each { |message| errors.add(:base, message) } if analyzed?
  end

  def analysis_errors
    messages = []
    summary = analysis["summary"].to_s
    messages << "L'analyse porte un diagnostic (summary)." if summary.blank?
    messages << "Le diagnostic est trop long." if summary.length > SUMMARY_MAX_LENGTH
    if analysis["agronomy"] && !BioindicatorVocabulary::AGRONOMY.key?(analysis["agronomy"])
      messages << "État agronomique inconnu : #{analysis['agronomy']}."
    end
    messages.concat(BioindicatorVocabulary.indicator_errors(analysis["indicators"] || []))
    species = analysis["species"]
    return messages << "Les espèces de l'analyse sont une liste." unless species.is_a?(Array)

    ids = species.filter_map { |item| item["species_id"] if item.is_a?(Hash) }
    known = BioindicatorSpecies.where(id: ids).pluck(:id)
    species.each do |item|
      next messages << "Une espèce de l'analyse est un objet." unless item.is_a?(Hash)

      messages << "Chaque espèce vue porte son nom." if item["name"].blank?
      messages << "Fiche espèce inconnue : #{item['species_id']}." if item["species_id"] && !known.include?(item["species_id"])
      messages << "Confiance inconnue : #{item['confidence']}." if item["confidence"] && !CONFIDENCES.key?(item["confidence"])
      messages << "Abondance inconnue : #{item['abundance']}." if item["abundance"] && !ABUNDANCES.key?(item["abundance"])
    end
    messages.uniq
  end
end
