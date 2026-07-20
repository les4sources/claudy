module Experiences
  # Grille MENSUELLE des disponibilités d'une activité (epic #25 / passe UX
  # "mois complet"). Même logique de blocs que `WeekCalendar` (durée de
  # l'activité, enchaînement 8h-22h, pas de chevauchement), mais on affiche une
  # colonne par jour du mois (28 à 31) au lieu d'une par jour de la semaine.
  # Réutilise les constantes et helpers de `WeekCalendar` pour ne pas dupliquer
  # les bornes horaires ni le formatage des heures.
  class MonthCalendar
    DAY_START_MINUTES = WeekCalendar::DAY_START_MINUTES
    DAY_END_MINUTES   = WeekCalendar::DAY_END_MINUTES

    attr_reader :experience, :month_start

    # `month` accepte soit un `Date` (n'importe quel jour du mois visé), soit une
    # chaîne "YYYY-MM" (le paramètre navigué). Tout ce qui n'est pas parsable
    # retombe sur le mois courant : la grille reste toujours affichable.
    def initialize(experience:, month: nil)
      @experience = experience
      @month_start = parse_month(month) || Date.today.beginning_of_month
    end

    def month_end
      month_start.end_of_month
    end

    # Toutes les dates du mois — 28 à 31 colonnes selon le mois.
    def days
      (month_start..month_end).to_a
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

    # Disponibilités du mois, indexées par [date, "HH:MM"].
    def availabilities_index
      @availabilities_index ||= experience.experience_availabilities
        .for_date_range(month_start, month_end)
        .index_by { |availability| [availability.available_on, availability.starts_at] }
    end

    def availability_at(day, minutes)
      availabilities_index[[day, WeekCalendar.format_minutes(minutes)]]
    end

    def previous_month = month_start.prev_month
    def next_month = month_start.next_month
    def current_month? = month_start == Date.today.beginning_of_month

    # Paramètres "YYYY-MM" pour construire les liens de navigation dans le frame.
    def month_param = month_start.strftime("%Y-%m")
    def previous_month_param = previous_month.strftime("%Y-%m")
    def next_month_param = next_month.strftime("%Y-%m")

    def format_minutes(minutes)
      WeekCalendar.format_minutes(minutes)
    end

    private

    def parse_month(value)
      return value.beginning_of_month if value.is_a?(Date)
      return nil if value.blank?

      Date.strptime(value.to_s, "%Y-%m").beginning_of_month
    rescue ArgumentError, Date::Error
      nil
    end
  end
end
