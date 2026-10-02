# Le vocabulaire des plantes bio-indicatrices, partagé par les fiches espèces
# (`BioindicatorSpecies`) et les relevés de la carte (`MapFeatureBioindicator`).
#
# Une plante bio-indicatrice dit l'état du sol par les conditions qui ont levé
# la dormance de sa graine : un sol engorgé, tassé, trop riche en azote… Les
# deux notes reprennent la lecture usuelle des fiches de terrain : l'état
# AGRONOMIQUE du sol (dégradé, en cours de dégradation, équilibré) et l'état
# ÉCOLOGIQUE du milieu (anthropisé, en cours de dégradation, préservé).
#
# Les clés sont stables (anglais), les libellés français. Les indicateurs codés
# sont ce qui permet de cartographier le sol : « où le sol est-il engorgé ? ».
module BioindicatorVocabulary
  AGRONOMY = {
    "degraded" => "Sol dégradé",
    "degrading" => "Sol en cours de dégradation",
    "balanced" => "Sol équilibré"
  }.freeze
  AGRONOMY_COLORS = { "degraded" => "#B42318", "degrading" => "#D9A21B", "balanced" => "#2E7D4F" }.freeze

  ECOLOGY = {
    "anthropized" => "Milieu anthropisé, dégradé",
    "degrading" => "Milieu en cours de dégradation",
    "preserved" => "Milieu préservé"
  }.freeze

  INDICATORS = {
    "waterlogging" => "Engorgement, hydromorphie",
    "drought" => "Sol sec, filtrant",
    "compaction" => "Tassement, asphyxie",
    "nitrogen_excess" => "Excès d'azote",
    "nitrogen_poor" => "Azote peu disponible",
    "organic_excess" => "Matière organique en excès, mal décomposée",
    "organic_poor" => "Pauvreté en matière organique",
    "carbon_excess" => "Excès de carbone (paille, fibres, crottin)",
    "acidic" => "Sol acide",
    "basic" => "Sol basique, calcaire",
    "base_rich" => "Sol riche en bases",
    "overgrazing" => "Surpâturage, piétinement",
    "disturbance" => "Sol remanié, travaillé",
    "erosion" => "Érosion, sol mis à nu",
    "biological_activity" => "Bonne activité biologique"
  }.freeze

  # La force d'un indicateur : un signe léger, net ou fort.
  STRENGTHS = { 1 => "léger", 2 => "net", 3 => "fort" }.freeze

  module_function

  # Une liste d'indicateurs : [{ "key" => …, "strength" => 1..3 }]. Rend les
  # messages d'erreur (vide = valide).
  def indicator_errors(list)
    return ["Les indicateurs sont une liste."] unless list.is_a?(Array)

    list.flat_map do |item|
      next ["Un indicateur est un objet { key, strength }."] unless item.is_a?(Hash)

      key = item["key"]
      strength = item["strength"]
      messages = []
      messages << "Indicateur inconnu : #{key}." unless INDICATORS.key?(key)
      messages << "La force d'un indicateur va de 1 à 3." unless STRENGTHS.key?(strength)
      messages
    end.uniq
  end

  # Les clés et forces nettoyées : chaînes, entiers, une seule fois chaque clé
  # (la plus forte).
  def normalize_indicators(list)
    return list unless list.is_a?(Array)

    list.filter_map do |item|
      next item unless item.respond_to?(:to_h)

      item = item.to_h.stringify_keys
      { "key" => item["key"].to_s.strip, "strength" => Integer(item["strength"].to_s, exception: false) || item["strength"] }
    end.group_by { |item| item["key"] }.map { |_, items| items.max_by { |item| item["strength"].to_i } }
  end

  def indicator_label(key) = INDICATORS[key]
end
