# Publication d'une fiche sur le site les4sources.be (événements, activités).
#
# Une fiche est publiée quand `published_at` est posé. Son `slug` est l'URL
# publique : proposé depuis le contenu (`slug_base`), modifiable tant que la
# fiche est un brouillon, dédoublonné par suffixe `-2`, `-3` sur TOUTES les
# lignes (soft-deleted comprises, l'index unique ne connaît pas la corbeille),
# et figé tant que la fiche est publiée — le site statique et les moteurs de
# recherche ont mémorisé l'adresse.
#
# Toute sauvegarde d'une fiche publiée (ou qui vient de l'être / de cesser de
# l'être) demande une reconstruction du site (`WebsiteRebuildJob`).
#
# Le modèle hôte définit `slug_base` (String) et `public_path_prefix`
# (« /evenements », « /catalogue »).
module Publishable
  extend ActiveSupport::Concern

  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  included do
    scope :published, -> { where.not(published_at: nil) }
    scope :draft, -> { where(published_at: nil) }

    before_validation :normalize_slug
    before_validation :assign_slug_if_publishing

    validates :slug,
              format: { with: SLUG_FORMAT, message: "ne peut contenir que des minuscules, des chiffres et des tirets" },
              uniqueness: { case_sensitive: false },
              allow_blank: true
    validates :slug, presence: true, if: :published?
    validate :slug_frozen_once_published

    after_commit :request_website_rebuild
  end

  class_methods do
    # Premier slug libre dérivé de `base` (`base`, `base-2`, `base-3`…), en
    # regardant toutes les lignes, corbeille comprise.
    def unique_slug(base, excluding: nil)
      base = base.to_s.parameterize.presence || model_name.singular
      scope = unscoped
      scope = scope.where.not(id: excluding.id) if excluding&.persisted?
      candidate = base
      counter = 1
      while scope.exists?(slug: candidate)
        counter += 1
        candidate = "#{base}-#{counter}"
      end
      candidate
    end
  end

  def published?
    published_at.present?
  end

  def draft?
    !published?
  end

  # Slug qui serait attribué à la publication — pour l'afficher dans le
  # formulaire sans rien écrire.
  def suggested_slug
    slug.presence || self.class.unique_slug(slug_base, excluding: self)
  end

  def public_path
    return nil if slug.blank?

    "#{public_path_prefix}/#{slug}"
  end

  private

  def normalize_slug
    self.slug = slug.to_s.strip.parameterize.presence
  end

  def assign_slug_if_publishing
    return unless published? && slug.blank?

    self.slug = self.class.unique_slug(slug_base, excluding: self)
  end

  # Figé tant que la fiche est en ligne : une fiche publiée avant cette
  # sauvegarde ne peut pas changer de slug. Dépublier garde le slug (l'adresse
  # reste réservée) mais le libère — hors ligne, changer d'adresse est un acte
  # délibéré.
  def slug_frozen_once_published
    return unless persisted? && slug_changed? && published_at_was.present?

    errors.add(:slug, "ne peut plus changer une fois la fiche publiée")
  end

  def request_website_rebuild
    return unless published? || saved_change_to_published_at?

    WebsiteRebuildJob.request!
  end
end
