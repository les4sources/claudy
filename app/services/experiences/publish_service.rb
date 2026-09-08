module Experiences
  # Publie / dépublie une activité sur le site (catalogue). Voir
  # `Events::PublishService` — mêmes règles : slug posé une seule fois, gardé à
  # la dépublication.
  class PublishService
    attr_reader :experience

    def initialize(experience:)
      @experience = experience
    end

    def publish!(slug: nil)
      experience.slug = slug if slug.present?
      experience.published_at ||= Time.current
      experience.save!
      experience
    end

    def unpublish!
      experience.published_at = nil
      experience.save!
      experience
    end
  end
end
