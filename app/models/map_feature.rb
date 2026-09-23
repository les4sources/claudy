# Un objet de la carte du domaine (epic #348, phase 2) : une zone, un accès, un
# point — et, aux phases suivantes, une plante, un nœud de réseau, un
# commentaire. Le modèle est commun, la couche dit à quoi il sert.
#
# La géométrie est du GeoJSON (`Point`, `LineString`, `Polygon`) stocké tel
# quel en jsonb (décision 12). Le nom et la description sont traduits en
# données (`{fr, en, nl}`, décision 4) avec repli sur le français : seuls les
# objets vus par les hôtes (couche Accueil, phase 4) auront besoin des trois.
class MapFeature < ApplicationRecord
  FEATURE_KINDS = %w[zone path point plant node line comment observation lodging space].freeze
  GEOMETRY_TYPES = %w[Point LineString Polygon].freeze
  LOCALES = %w[fr en nl].freeze
  PHOTO_CONTENT_TYPES = %w[image/jpeg image/png image/heic image/heif].freeze
  HEIC_CONTENT_TYPES = %w[image/heic image/heif].freeze
  # Ce qu'un objet de la carte peut représenter (phase 3). Liste fermée : le
  # type polymorphe vient d'un formulaire, il ne doit jamais désigner autre
  # chose qu'un gîte ou une salle.
  LINKABLE_TYPES = { "Lodging" => "lodging", "Space" => "space" }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :map_layer
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :linked, polymorphic: true, optional: true

  # Miniature pour la galerie, aperçu pour l'agrandissement. `format: :jpeg` :
  # une photo HEIC d'iPhone n'est pas lisible par tous les navigateurs.
  has_many_attached :photos do |attachable|
    attachable.variant :thumb, resize_to_limit: [320, 320], format: :jpeg
    attachable.variant :preview, resize_to_limit: [1600, 1600], format: :jpeg
  end

  validates :feature_kind, inclusion: { in: FEATURE_KINDS }
  validate :geometry_is_valid_geojson
  validate :photos_are_images
  validates :linked_type, inclusion: { in: LINKABLE_TYPES.keys }, allow_nil: true
  validate :linked_only_once

  scope :ordered, -> { order(:position, :id) }

  before_validation :normalize_geometry

  # La géométrie dit le type d'objet quand on ne l'a pas précisé : un polygone
  # est une zone, une ligne un accès, un point un point.
  def self.kind_for_geometry(geometry)
    case geometry.is_a?(Hash) && geometry["type"]
    when "Polygon" then "zone"
    when "LineString" then "path"
    else "point"
    end
  end

  # Les variantes passent par libvips (processeur par défaut de Rails 8.1),
  # retiré du serveur de production (cf. Gemfile). Sans lui, une miniature
  # répondrait en erreur : la galerie montre alors l'original, réduit en CSS.
  def self.image_variants?
    return @image_variants if defined?(@image_variants)

    @image_variants = begin
      require "vips"
      true
    rescue LoadError, StandardError
      false
    end
  end

  # Une photo HEIC d'iPhone ne s'affiche que dans Safari : on ne l'accepte que
  # si libvips sait la décoder, pour la servir en miniature JPEG. Sinon elle
  # est refusée avec un message clair (spec de la phase 2), plutôt qu'acceptée
  # puis cassée sur Chrome, Firefox et Android.
  def self.heic_supported?
    return @heic_supported if defined?(@heic_supported)

    @heic_supported = image_variants? && Vips.get_suffixes.include?(".heic")
  rescue StandardError
    @heic_supported = false
  end

  def self.accepted_photo_types
    heic_supported? ? PHOTO_CONTENT_TYPES : PHOTO_CONTENT_TYPES - HEIC_CONTENT_TYPES
  end

  def self.photo_source(photo, variant)
    image_variants? ? photo.variant(variant) : photo
  end

  def name(locale = I18n.locale) = translated(name_i18n, locale)
  def description(locale = I18n.locale) = translated(description_i18n, locale)

  def geometry_type = geometry.is_a?(Hash) ? geometry["type"] : nil

  def management_notes = properties.to_h["management_notes"]

  # « Lodging:3 » : la valeur du sélecteur de la fiche. Le setter ne constantize
  # rien — un type hors de `LINKABLE_TYPES` est ignoré, jamais résolu.
  def linked_key = linked_type && linked_id ? "#{linked_type}:#{linked_id}" : ""

  def linked_key=(value)
    type, id = value.to_s.split(":", 2)
    if LINKABLE_TYPES.key?(type) && id.to_s.match?(/\A\d+\z/)
      self.linked_type = type
      self.linked_id = id.to_i
      self.feature_kind = LINKABLE_TYPES.fetch(type)
    else
      self.feature_kind = MapFeature.kind_for_geometry(geometry) if venue?
      self.linked_type = nil
      self.linked_id = nil
    end
  end

  def venue? = LINKABLE_TYPES.value?(feature_kind)

  # Un objet de la carte dans une `FeatureCollection` GeoJSON : la géométrie,
  # et ce dont la carte a besoin pour le dessiner et l'étiqueter.
  def as_geojson
    {
      type: "Feature",
      id: id,
      geometry: geometry,
      properties: {
        id: id,
        feature_kind: feature_kind,
        name: name(:fr).presence || linked&.name,
        layer_id: map_layer_id,
        linked_type: linked_type,
        linked_id: linked_id,
        photos_count: photos.size,
        properties: properties
      }
    }
  end

  private

  def translated(values, locale)
    values = values.to_h
    values[locale.to_s].presence || values["fr"].presence
  end

  # Le formulaire envoie la géométrie comme une chaîne JSON (champ caché mis à
  # jour par Geoman) : on la parse ici pour que la validation voie un Hash.
  def normalize_geometry
    return unless geometry.is_a?(String)

    self.geometry = JSON.parse(geometry)
  rescue JSON::ParserError
    self.geometry = { "invalid" => geometry }
  end

  def geometry_is_valid_geojson
    return errors.add(:geometry, "est obligatoire") if geometry.blank?
    return errors.add(:geometry, "n'est pas un GeoJSON valide") unless geometry.is_a?(Hash)

    type = geometry["type"]
    coords = geometry["coordinates"]
    valid =
      case type
      when "Point" then position?(coords)
      when "LineString" then coords.is_a?(Array) && coords.size >= 2 && coords.all? { |c| position?(c) }
      when "Polygon" then coords.is_a?(Array) && coords.any? && coords.all? { |ring| linear_ring?(ring) }
      else false
      end

    errors.add(:geometry, "doit être un Point, une LineString ou un Polygon GeoJSON valide") unless valid
  end

  def position?(value)
    value.is_a?(Array) && value.size.between?(2, 3) && value.all? { |n| n.is_a?(Numeric) } &&
      value[0].between?(-180, 180) && value[1].between?(-90, 90)
  end

  # Un anneau GeoJSON : au moins quatre positions, la dernière égale à la
  # première.
  def linear_ring?(ring)
    ring.is_a?(Array) && ring.size >= 4 && ring.all? { |c| position?(c) } && ring.first == ring.last
  end

  def linked_only_once
    return if linked_type.blank? || linked_id.blank?

    taken = MapFeature.where(linked_type: linked_type, linked_id: linked_id)
    taken = taken.where.not(id: id) if persisted?
    errors.add(:linked, "a déjà son tracé sur la carte") if taken.exists?
  end

  def photos_are_images
    photos.each do |photo|
      type = photo.blob.content_type
      next if MapFeature.accepted_photo_types.include?(type)

      if HEIC_CONTENT_TYPES.include?(type)
        errors.add(:photos, "« #{photo.filename} » est au format HEIC, que le serveur ne sait pas convertir : " \
                            "exportez-la en JPEG (sur iPhone : Réglages › Appareil photo › Formats › « Le plus compatible »)")
      else
        errors.add(:photos, "« #{photo.filename} » n'est pas une photo acceptée (#{MapFeature.heic_supported? ? 'JPEG, PNG ou HEIC' : 'JPEG ou PNG'})")
      end
    end
  end
end
