module Events
  # Publie / dépublie un événement sur le site. La publication pose
  # `published_at` et, si nécessaire, le slug (une seule fois : `Publishable`
  # le fige ensuite). Dépublier retire la fiche du site mais garde le slug —
  # l'adresse reste réservée pour une éventuelle republication.
  class PublishService
    attr_reader :event

    def initialize(event:)
      @event = event
    end

    def publish!(slug: nil)
      event.slug = slug if slug.present?
      event.published_at ||= Time.current
      event.save!
      event
    end

    def unpublish!
      event.published_at = nil
      event.save!
      event
    end
  end
end
