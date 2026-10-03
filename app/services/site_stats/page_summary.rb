module SiteStats
  # Les visites d'UNE page du site, pour l'encart « Site web » d'une fiche
  # événement ou activité dans Claudy (2026-10-03). Même convention que
  # `Report` : une visite = une empreinte du jour.
  class PageSummary
    RECENT_DAYS = 30

    def initialize(path, today: Time.zone.today)
      @path = path
      @today = today
    end

    def any? = total_visits.positive?

    def recent_visits = recent.pageviews.distinct.count(:visitor_hash)

    def total_visits
      @total_visits ||= all.pageviews.distinct.count(:visitor_hash)
    end

    def recent_clicks = recent.events(Report::CLICK_EVENTS).count

    def recent_submissions = recent.events("tally_submit").count

    def tracked_since = all.minimum(:day)

    private

    def all
      SiteHit.where(path: @path)
    end

    def recent
      all.between(@today - (RECENT_DAYS - 1), @today)
    end
  end
end
