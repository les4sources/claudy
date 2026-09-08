module Api
  module Public
    module V1
      class EventsController < BaseController
        DEFAULT_LOOKBACK = 365

        # GET /api/public/v1/events?from=YYYY-MM-DD&to=YYYY-MM-DD
        # Événements publiés (non supprimés) qui se terminent après `from`
        # (défaut : il y a un an, pour garder les fiches passées) et commencent
        # avant `to`.
        def index
          from = parse_date(params[:from]) || DEFAULT_LOOKBACK.days.ago.to_date
          to = parse_date(params[:to])

          scope = Event.published
                       .includes(:event_category, :rich_text_public_description, image_attachment: :blob)
                       .where("events.ends_at >= ?", from.beginning_of_day)
                       .order(:starts_at, :id)
          scope = scope.where("events.starts_at <= ?", to.end_of_day) if to
          @events = scope.to_a

          # ETag à la microseconde (`cache_key_with_version`) : deux
          # sauvegardes dans la même seconde doivent donner deux ETags.
          serve_cached([
            "events",
            from,
            to,
            @events.map(&:cache_key_with_version),
            EventCategory.unscoped.maximum(:updated_at)&.to_f
          ])
        end
      end
    end
  end
end
