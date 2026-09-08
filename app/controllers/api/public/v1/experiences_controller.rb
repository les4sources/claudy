module Api
  module Public
    module V1
      class ExperiencesController < BaseController
        AVAILABILITY_HORIZON = 6.months

        # GET /api/public/v1/experiences — activités publiées, avec leurs
        # créneaux à venir (six mois) et les places restantes.
        def index
          @experiences = Experience.published
                                   .includes(:human, :rich_text_description)
                                   .order(:name, :id)
                                   .to_a
          horizon = Date.today..(Date.today + AVAILABILITY_HORIZON)
          @availabilities = ExperienceAvailability
                            .where(experience_id: @experiences.map(&:id), available_on: horizon)
                            .includes(:experience_bookings)
                            .order(:available_on, :starts_at)
                            .group_by(&:experience_id)

          serve_cached([
            "experiences",
            @experiences.map(&:cache_key_with_version),
            @availabilities.values.flatten.map(&:cache_key_with_version),
            ExperienceBooking.unscoped.maximum(:updated_at)&.to_f
          ])
        end
      end
    end
  end
end
