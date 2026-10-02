# Une note manuscrite de la carte du domaine (epic #348, phase 12) : des traits
# dessinés à main levée par-dessus la carte, au stylet, au doigt ou à la souris.
#
# Le dessin porte lui-même son nom et son dossier (pas de `MapLayer` par dessin,
# voir la migration). Ses tracés sont en coordonnées géographiques : ils restent
# à leur place à tout zoom et sur tout fond.
#
#   strokes = [{ "id" => "k3f9a2", "points" => [[lat, lng], …], "width" => 3 }, …]
#
# Attention à l'ordre : `[lat, lng]` (celui de Leaflet), PAS l'ordre GeoJSON.
#
# `lock_version` active le verrou optimiste de Rails : le client renvoie la
# version qu'il a lue, et un dessin modifié ailleurs entre-temps lève
# `ActiveRecord::StaleObjectError` (409 côté contrôleur).
class MapSketch < ApplicationRecord
  MAX_POINTS = 5_000
  MAX_STROKES = 2_000
  WIDTHS = (1..20)
  STROKE_ID = /\A[A-Za-z0-9_-]{1,40}\z/

  # Les tracés sont remplacés en bloc à chaque enregistrement automatique : les
  # garder dans chaque version PaperTrail ferait grossir la table des versions
  # au carré du nombre de traits. On suit le nom, le dossier, la suppression.
  has_paper_trail skip: %i[strokes lock_version]
  has_soft_deletion default_scope: true

  belongs_to :created_by, class_name: "User", optional: true

  validates :name, presence: true, length: { maximum: 120 }
  validates :folder, length: { maximum: 120 }
  validate :strokes_are_well_formed

  before_validation :normalize_labels

  # Sans dossier d'abord, puis par dossier et par nom, sans tenir compte de la
  # casse.
  scope :ordered, -> { order(Arel.sql("folder IS NOT NULL, LOWER(folder), LOWER(name), id")) }

  def strokes_count = strokes.is_a?(Array) ? strokes.size : 0

  # Ce que liste le panneau : pas les tracés, qui peuvent peser lourd.
  def as_summary
    { id: id, name: name, folder: folder, strokes_count: strokes_count, lock_version: lock_version,
      updated_at: updated_at&.iso8601 }
  end

  def as_detail = as_summary.merge(strokes: strokes)

  private

  def normalize_labels
    self.name = name.to_s.strip
    self.folder = folder.to_s.strip.presence
  end

  def strokes_are_well_formed
    return errors.add(:strokes, "doit être une liste de tracés") unless strokes.is_a?(Array)
    return errors.add(:strokes, "ne peut dépasser #{MAX_STROKES} tracés par dessin") if strokes.size > MAX_STROKES

    bad = strokes.find_index { |stroke| !valid_stroke?(stroke) }
    errors.add(:strokes, "contient un tracé invalide (n° #{bad + 1})") if bad
  end

  def valid_stroke?(stroke)
    return false unless stroke.is_a?(Hash)

    id, points, width = stroke.values_at("id", "points", "width")
    id.is_a?(String) && id.match?(STROKE_ID) &&
      width.is_a?(Numeric) && WIDTHS.cover?(width) &&
      points.is_a?(Array) && points.size.between?(1, MAX_POINTS) &&
      points.all? { |point| latlng?(point) }
  end

  def latlng?(point)
    point.is_a?(Array) && point.size == 2 && point.all? { |n| n.is_a?(Numeric) } &&
      point[0].between?(-90, 90) && point[1].between?(-180, 180)
  end
end
