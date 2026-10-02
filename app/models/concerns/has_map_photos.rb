# Les photos d'un objet de la carte (phase 2) ou d'une plante (phase 7) :
# miniature pour la galerie, aperçu pour l'agrandissement, et le même refus
# clair d'une photo que le serveur ne saurait pas afficher.
#
# Les méthodes de classe (`MapFeature.photo_source`, `Plant.accepted_photo_types`…)
# passent toutes par `image_variants?` et `heic_supported?` de la classe : c'est
# ce que les specs surchargent. La détection de libvips, elle, n'est faite
# qu'une fois pour toute l'application.
module HasMapPhotos
  extend ActiveSupport::Concern

  PHOTO_CONTENT_TYPES = %w[image/jpeg image/png image/heic image/heif].freeze
  HEIC_CONTENT_TYPES = %w[image/heic image/heif].freeze

  included do
    # `format: :jpeg` : une photo HEIC d'iPhone n'est pas lisible par tous les
    # navigateurs.
    has_many_attached :photos do |attachable|
      attachable.variant :thumb, resize_to_limit: [320, 320], format: :jpeg
      attachable.variant :preview, resize_to_limit: [1600, 1600], format: :jpeg
    end

    validate :photos_are_images
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
  # si libvips sait la décoder, pour la servir en miniature JPEG.
  def self.heic_supported?
    return @heic_supported if defined?(@heic_supported)

    @heic_supported = image_variants? && Vips.get_suffixes.include?(".heic")
  rescue StandardError
    @heic_supported = false
  end

  class_methods do
    def image_variants? = HasMapPhotos.image_variants?
    def heic_supported? = HasMapPhotos.heic_supported?

    def accepted_photo_types
      heic_supported? ? PHOTO_CONTENT_TYPES : PHOTO_CONTENT_TYPES - HEIC_CONTENT_TYPES
    end

    def photo_source(photo, variant)
      image_variants? ? photo.variant(variant) : photo
    end
  end

  # La première photo, en miniature : la liste « à placer » (phase 7).
  def first_photo_thumb
    photo = photos.first
    photo && self.class.photo_source(photo, :thumb)
  end

  private

  def photos_are_images
    photos.each do |photo|
      type = photo.blob.content_type
      next if self.class.accepted_photo_types.include?(type)

      if HEIC_CONTENT_TYPES.include?(type)
        errors.add(:photos, "« #{photo.filename} » est au format HEIC, que le serveur ne sait pas convertir : " \
                            "exportez-la en JPEG (sur iPhone : Réglages › Appareil photo › Formats › « Le plus compatible »)")
      else
        errors.add(:photos, "« #{photo.filename} » n'est pas une photo acceptée " \
                            "(#{self.class.heic_supported? ? 'JPEG, PNG ou HEIC' : 'JPEG ou PNG'})")
      end
    end
  end
end
