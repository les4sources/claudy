module Experiences
  # Grille hebdomadaire des disponibilités d'une activité (epic #25, Phase 4).
  # Les créneaux ont tous la durée de l'activité (`duration_hours`), s'enchaînent
  # sans trou entre 8h et 22h, et ne se chevauchent jamais : poser un bloc, c'est
  # cliquer une case de cette grille.
  class WeekCalendar
    DAY_START_MINUTES = 8 * 60   # 08:00
    DAY_END_MINUTES   = 22 * 60  # 22:00

    attr_reader :experience, :week_start

    def initialize(experience:, week_start: nil)
      @experience = experience
      @week_start = (week_start.presence || Date.today).beginning_of_week(:monday)
    end

    def days
      (week_start..week_start.end_of_week(:monday)).to_a
    end

    def block_minutes
      experience.block_duration_minutes.to_i
    end

    # Sans durée numérique sur l'activité, on ne sait pas quelle taille de bloc
    # poser : la grille ne s'affiche pas et on invite à renseigner la durée.
    def configured?
      block_minutes.positive?
    end

    # Heures de début candidates, en minutes depuis minuit. Un bloc qui
    # dépasserait 22h n'est pas proposé.
    def slot_starts
      return [] unless configured?

      starts = []
      minutes = DAY_START_MINUTES
      while minutes + block_minutes <= DAY_END_MINUTES
        starts << minutes
        minutes += block_minutes
      end
      starts
    end

    # Disponibilités de la semaine, indexées par [date, "HH:MM"].
    def availabilities_index
      @availabilities_index ||= experience.experience_availabilities
        .for_date_range(days.first, days.last)
        .index_by { |availability| [availability.available_on, availability.starts_at] }
    end

    def availability_at(day, minutes)
      availabilities_index[[day, self.class.format_minutes(minutes)]]
    end

    def previous_week = week_start - 7
    def next_week = week_start + 7
    def current_week? = week_start == Date.today.beginning_of_week(:monday)

    def self.format_minutes(minutes)
      format("%02d:%02d", minutes / 60, minutes % 60)
    end

    def self.parse_time(value)
      return nil if value.blank?

      hours, minutes = value.to_s.split(":").map(&:to_i)
      return nil if hours.nil? || minutes.nil?

      (hours * 60) + minutes
    end
  end
end
