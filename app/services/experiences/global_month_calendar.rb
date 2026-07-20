module Experiences
  # Calendrier global MENSUEL des créneaux, toutes activités confondues
  # (demande Michael 2026-07-20 — remplace la vue semaine de l'epic #25).
  # Une ligne par activité ayant au moins un créneau dans le mois, une colonne
  # par jour, et le NOMBRE de créneaux posés ce jour-là (pas le détail).
  class GlobalMonthCalendar
    attr_reader :month

    def initialize(month: nil, human_id: nil)
      @human_id = human_id
      base = case month
             when Date then month
             when /\A\d{4}-\d{2}\z/ then (Date.parse("#{month}-01") rescue Date.today)
             else Date.today
             end
      @month = base.beginning_of_month
    end

    def days
      @days ||= (@month..@month.end_of_month).to_a
    end

    def month_param  = @month.strftime("%Y-%m")
    def previous_month = @month.prev_month
    def next_month     = @month.next_month

    def current_month?
      @month == Date.today.beginning_of_month
    end

    # [[Experience, { date => count }], …] trié par nom — uniquement les
    # activités qui ont au moins un créneau dans le mois affiché.
    def rows
      @rows ||= begin
        availabilities = ExperienceAvailability.where(available_on: days.first..days.last)
        # Cloisonnement porteur restreint : ne compter que ses propres activités.
        if @human_id
          availabilities = availabilities.joins(:experience)
                                         .where(experiences: { human_id: @human_id })
        end
        counts = availabilities
                 .group(:experience_id, :available_on)
                 .count
        by_experience = {}
        counts.each do |(experience_id, date), count|
          (by_experience[experience_id] ||= {})[date] = count
        end
        Experience.where(id: by_experience.keys).order(name: :asc)
                  .map { |experience| [experience, by_experience[experience.id]] }
      end
    end

    def any?
      rows.any?
    end
  end
end
