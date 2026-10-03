module SiteStats
  # Les chiffres du tableau de bord « Site web » sur une période (statistiques
  # sans cookie, 2026-10-03).
  #
  # Une VISITE = une empreinte du jour (`visitor_hash`). Le sel changeant chaque
  # jour, quelqu'un qui revient trois jours compte trois visites : c'est le prix
  # du sans-cookie, et c'est la même convention que Plausible. Comme l'appareil
  # entre dans l'empreinte, une visite a un seul appareil, navigateur et pays.
  #
  # L'entrée d'une visite est sa première page vue : elle donne la page
  # d'arrivée et la source (Google, Facebook, accès direct, campagne…).
  class Report
    PERIODS = { "7" => "7 jours", "30" => "30 jours", "90" => "90 jours", "365" => "12 mois" }.freeze
    DEFAULT_PERIOD = "30".freeze
    REALTIME_WINDOW = 30.minutes
    TOP = 15

    EVENT_LABELS = {
      "reservation" => "Clic « Réserver »",
      "tally" => "Ouverture d'un formulaire Tally",
      "tally_submit" => "Formulaire Tally envoyé",
      "telephone" => "Clic sur le téléphone",
      "email" => "Clic sur l'e-mail",
      "outbound" => "Lien vers un autre site"
    }.freeze

    FUNNEL_STEPS = [
      ["Visites du site", nil],
      ["Clic « Réserver »", "reservation"],
      ["Étape 1 du funnel — dates", "funnel_dates"],
      ["Étape 3 du funnel — coordonnées", "funnel_contact"],
      ["Demande de réservation envoyée", "funnel_request"]
    ].freeze

    attr_reader :period, :from, :to

    def initialize(period: DEFAULT_PERIOD, today: Time.zone.today)
      @period = PERIODS.key?(period.to_s) ? period.to_s : DEFAULT_PERIOD
      @to = today
      @from = today - (@period.to_i - 1)
    end

    def period_label = PERIODS[period]

    def previous
      @previous ||= self.class.new(period: period, today: from - 1)
    end

    def empty? = pageviews.zero? && funnel_hits.none?

    # — Indicateurs —

    def visits
      @visits ||= pageview_scope.distinct.count(:visitor_hash)
    end

    def pageviews
      @pageviews ||= pageview_scope.count
    end

    def pages_per_visit
      visits.zero? ? 0.0 : (pageviews.to_f / visits).round(1)
    end

    # Part des visites qui n'ont vu qu'une page.
    def bounce_rate
      return 0.0 if visits.zero?

      single = pageview_scope.group(:visitor_hash).having("COUNT(*) = 1").count.size
      (single * 100.0 / visits).round(0)
    end

    def requests
      @requests ||= funnel_hits.where(name: "funnel_request").distinct.count(:visitor_hash)
    end

    def current_visitors(now: Time.current)
      SiteHit.pageviews.where(occurred_at: (now - REALTIME_WINDOW)..now).distinct.count(:visitor_hash)
    end

    # Évolution par rapport à la période précédente, en pour cent (nil si la
    # période précédente est vide : une hausse « infinie » ne se lit pas).
    def change(metric)
      before = previous.public_send(metric).to_f
      return nil if before.zero?

      ((public_send(metric).to_f - before) * 100 / before).round(0)
    end

    # — Série quotidienne —

    def daily
      @daily ||= begin
        views = pageview_scope.group(:day).count
        uniques = pageview_scope.group(:day).distinct.count(:visitor_hash)
        (from..to).map { |day| { day: day, visits: uniques[day].to_i, pageviews: views[day].to_i } }
      end
    end

    # — Tableaux —

    def top_pages
      rows(pageview_scope.group(:path)
                         .order(Arel.sql("COUNT(*) DESC"))
                         .limit(TOP)
                         .pluck(:path, Arel.sql("COUNT(DISTINCT visitor_hash)"), Arel.sql("COUNT(*)")),
           %i[label visits pageviews])
    end

    def entry_pages = entries_breakdown(:path)

    def sources = entries_breakdown(Arel.sql("COALESCE(source, 'Accès direct')"))

    def campaigns
      rows(SiteHit.from(entries, :site_hits)
                  .where("utm_campaign IS NOT NULL OR utm_source IS NOT NULL")
                  .group(Arel.sql("COALESCE(utm_campaign, '—')"), Arel.sql("COALESCE(utm_source, '—')"), Arel.sql("COALESCE(utm_medium, '—')"))
                  .order(Arel.sql("COUNT(*) DESC"))
                  .limit(TOP)
                  .pluck(Arel.sql("COALESCE(utm_campaign, '—')"), Arel.sql("COALESCE(utm_source, '—')"),
                         Arel.sql("COALESCE(utm_medium, '—')"), Arel.sql("COUNT(*)")),
           %i[campaign source medium visits])
    end

    def devices = visits_by(:device)

    def browsers = visits_by(:browser)

    def operating_systems = visits_by(:os)

    COUNTRY_NAMES = {
      "BE" => "Belgique", "FR" => "France", "NL" => "Pays-Bas", "LU" => "Luxembourg",
      "DE" => "Allemagne", "GB" => "Royaume-Uni", "CH" => "Suisse", "ES" => "Espagne",
      "IT" => "Italie", "PT" => "Portugal", "US" => "États-Unis", "CA" => "Canada"
    }.freeze

    def countries
      visits_by(:country, missing: "Inconnu").map { |row| row.merge(label: COUNTRY_NAMES.fetch(row[:label], row[:label])) }
    end

    def events
      counts = SiteHit.between(from, to).events(EVENT_LABELS.keys).group(:name).count
      uniques = SiteHit.between(from, to).events(EVENT_LABELS.keys).group(:name).distinct.count(:visitor_hash)
      EVENT_LABELS.map { |name, label| { label: label, count: counts[name].to_i, visits: uniques[name].to_i } }
    end

    # D'où part le clic « Réserver » : la page du site où il a eu lieu.
    def reservation_pages
      grouped_events("reservation", :path)
    end

    def tally_forms
      grouped_events("tally_submit", :target)
    end

    def not_found_pages
      grouped_events("not_found", :path)
    end

    # — Entonnoir de réservation —

    def funnel
      FUNNEL_STEPS.map do |label, name|
        count = name ? SiteHit.between(from, to).events(name).distinct.count(:visitor_hash) : visits
        { label: label, count: count }
      end.then do |steps|
        top = steps.first[:count]
        steps.map { |step| step.merge(share: top.zero? ? nil : (step[:count] * 100.0 / top).round(1)) }
      end
    end

    # Demandes de réservation envoyées, rangées par source de la visite du site
    # qui les a précédées le même jour. Une demande sans visite du site (lien
    # direct vers le funnel, e-mail…) est rangée à part.
    def requests_by_source
      hashes = funnel_hits.where(name: "funnel_request").distinct.pluck(:visitor_hash)
      return [] if hashes.empty?

      by_hash = SiteHit.from(entries, :site_hits).where(visitor_hash: hashes)
                       .pluck(:visitor_hash, Arel.sql("COALESCE(source, 'Accès direct')")).to_h
      hashes.map { |hash| by_hash[hash] || "Sans visite du site" }
            .tally.sort_by { |label, count| [-count, label] }
            .map { |label, count| { label: label, count: count } }
    end

    private

    def pageview_scope
      SiteHit.pageviews.between(from, to)
    end

    def funnel_hits
      SiteHit.between(from, to).events(SiteHit::FUNNEL_EVENTS)
    end

    # La première page vue de chaque visite.
    def entries
      @entries ||= pageview_scope.select("DISTINCT ON (visitor_hash) site_hits.*")
                                 .reorder(:visitor_hash, :occurred_at, :id)
    end

    def entries_breakdown(column)
      rows(SiteHit.from(entries, :site_hits)
                  .group(column)
                  .order(Arel.sql("COUNT(*) DESC"))
                  .limit(TOP)
                  .pluck(column, Arel.sql("COUNT(*)")),
           %i[label visits])
    end

    def visits_by(column, missing: "Autre")
      rows(pageview_scope.group(column).distinct.count(:visitor_hash)
                         .sort_by { |label, count| [-count, label.to_s] }
                         .first(TOP)
                         .map { |label, count| [label.presence || missing, count] },
           %i[label visits])
        .map { |row| row.merge(share: visits.zero? ? 0 : (row[:visits] * 100.0 / visits).round(0)) }
    end

    def grouped_events(name, column)
      rows(SiteHit.between(from, to).events(name)
                  .group(column)
                  .order(Arel.sql("COUNT(*) DESC"))
                  .limit(TOP)
                  .pluck(column, Arel.sql("COUNT(*)")),
           %i[label count])
    end

    def rows(tuples, keys)
      tuples.map { |values| keys.zip(Array(values)).to_h }
    end
  end
end
