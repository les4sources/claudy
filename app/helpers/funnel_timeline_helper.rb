# Ligne du temps de la réservation, à l'étape Coordonnées (Michael, 2026-10-03 :
# « un récapitulatif visuel, en représentant le séjour sous la forme d'une ligne
# du temps »).
#
# Chaque JOUR, de l'arrivée au départ inclus, occupe deux demi-colonnes :
# « journée » puis « soirée ». C'est ce qui permet de tout poser sur le même
# axe sans tricher :
#   · une NUIT (gîte, tente, van, hamac) va de la soirée du jour J à la
#     journée du jour J+1 — la barre du gîte part le soir de l'arrivée et
#     s'arrête le matin du départ ;
#   · une SALLE se pose sur la journée, la soirée ou les deux d'un jour.
#
# Les colonnes rendues sont des numéros de grille CSS, 1-indexés, sans la
# colonne d'intitulé (la vue la gère à part).
module FunnelTimelineHelper
  # `icons` : sur mobile, une demi-colonne ne fait qu'une quarantaine de
  # pixels — « Journée » y serait tronqué. Les salles y montrent un soleil
  # (journée) et/ou une lune (soirée), le texte restant lu à l'écran.
  Segment = Data.define(:from, :to, :text, :icons) do
    def initialize(from:, to:, text:, icons: []) = super
  end
  Row = Data.define(:label, :kind, :segments)
  Timeline = Data.define(:days, :rows)

  SPACE_NAMES = { "grande_salle" => "Grande Salle", "petite_salle" => "Petite Salle", "cuisine_pro" => "Cuisine pro" }.freeze
  SLOT_SPANS = {
    "journee" => [0, 1, "Journée", %i[sun]],
    "soiree" => [1, 2, "Soirée", %i[moon]],
    "journee_et_soiree" => [0, 2, "Journée + soirée", %i[sun moon]]
  }.freeze

  def reservation_timeline(draft)
    return nil unless draft.arrival_date && draft.departure_date && draft.departure_date >= draft.arrival_date

    days = (draft.arrival_date..draft.departure_date).to_a
    rows = timeline_lodging_rows(draft) + timeline_space_rows(draft, days) + timeline_outdoor_rows(draft)
    return nil if rows.empty?

    Timeline.new(days: days, rows: rows)
  end

  # Grille CSS de la nuit `index` : soirée du jour J → journée du jour J+1.
  def timeline_night_columns(index)
    [2 * index + 2, 2 * index + 4]
  end

  private

  def timeline_lodging_rows(draft)
    ids = Array(draft.lodging_night_ids).first(draft.nights)
    ids = Array.new(draft.nights, draft.lodging_id) if ids.compact_blank.empty? && draft.lodging_id.present?
    return [] if ids.compact_blank.empty?

    names = Lodging.where(id: ids.compact_blank.uniq).to_h { |l| [l.id.to_s, l.name] }
    segments = timeline_runs(ids.map { |id| id.presence && names[id.to_s] })
    [Row.new(label: "Hébergement", kind: "lodging", segments: segments)]
  end

  def timeline_space_rows(draft, days)
    (draft.space_slots || {}).filter_map do |key, slots|
      segments = Array(slots).first(days.size).each_with_index.filter_map do |value, i|
        start, finish, text, icons = SLOT_SPANS[value.to_s]
        next unless start

        Segment.new(from: 2 * i + 1 + start, to: 2 * i + 1 + finish, text: text, icons: icons)
      end
      Row.new(label: SPACE_NAMES[key.to_s] || key.to_s.humanize, kind: "space", segments: segments) if segments.any?
    end
  end

  def timeline_outdoor_rows(draft)
    pnr = draft.per_night_resources || {}
    {
      "tente" => ["Camping", ->(n) { "#{n} pers." }],
      "van" => ["Van", ->(n) { n > 1 ? "#{n} vans" : "1 van" }],
      "hamac_simple" => ["Hamac simple", ->(n) { "× #{n}" }],
      "hamac_double" => ["Hamac double", ->(n) { "× #{n}" }]
    }.filter_map do |key, (label, text)|
      counts = draft.night_values(pnr[key]).map(&:to_i)
      segments = timeline_runs(counts.map { |n| n.positive? ? text.(n) : nil })
      Row.new(label: label, kind: "outdoor", segments: segments) if segments.any?
    end
  end

  # Regroupe les nuits consécutives de même valeur en une seule barre.
  def timeline_runs(values)
    values.each_with_index.slice_when { |(a, _), (b, _)| a != b }.filter_map do |run|
      text = run.first.first
      next if text.nil?

      Segment.new(from: timeline_night_columns(run.first.last).first,
                  to: timeline_night_columns(run.last.last).last, text: text)
    end
  end
end
