module Experiences
  # Calendrier hebdomadaire de TOUTES les activités (epic #25, Phase 5), affiché
  # au-dessus du tableau de l'index.
  #
  # Différence clé avec `Experiences::WeekCalendar` (calendrier d'UNE activité) :
  # ici, les activités ont des durées de bloc différentes et leurs créneaux ont le
  # droit de se chevaucher. Une grille de créneaux à pas fixe n'a donc pas de sens
  # — on retombe sur une grille à l'heure, et chaque créneau est rangé dans la
  # ligne de son heure de début. Plusieurs créneaux dans la même case s'empilent.
  class GlobalWeekCalendar
    START_HOUR = WeekCalendar::DAY_START_MINUTES / 60 # 8
    END_HOUR   = WeekCalendar::DAY_END_MINUTES / 60   # 22

    attr_reader :week_start

    def initialize(week_start: nil)
      @week_start = (week_start.presence || Date.today).beginning_of_week(:monday)
    end

    def days
      (week_start..week_start.end_of_week(:monday)).to_a
    end

    # Lignes de la grille : 8h → 21h (un créneau qui démarre à 21h30 se range dans
    # la ligne 21h ; rien ne peut démarrer à 22h, c'est la borne de fermeture).
    def hours
      (START_HOUR...END_HOUR).to_a
    end

    def availabilities
      @availabilities ||= ExperienceAvailability
        .includes(:experience)
        .for_date_range(days.first, days.last)
        .to_a
        .sort_by { |availability| [availability.available_on, availability.starts_at_minutes || 0] }
    end

    # Créneaux indexés par [date, heure de début] — l'empilement dans une case est
    # simplement l'ordre chronologique puis alphabétique de l'activité, pour que
    # l'affichage soit stable d'un rendu à l'autre.
    def index
      @index ||= availabilities.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |availability, memo|
        minutes = availability.starts_at_minutes
        next if minutes.nil?

        memo[[availability.available_on, minutes / 60]] << availability
      end
    end

    def availabilities_at(day, hour)
      index[[day, hour]].sort_by { |availability| [availability.starts_at_minutes, availability.experience.name.to_s] }
    end

    def any?
      availabilities.any?
    end

    # Activités présentes dans la semaine affichée — sert à dessiner la légende
    # (une couleur par activité).
    def experiences
      @experiences ||= availabilities.map(&:experience).uniq.sort_by { |experience| experience.name.to_s }
    end

    def previous_week = week_start - 7
    def next_week = week_start + 7
    def current_week? = week_start == Date.today.beginning_of_week(:monday)
  end
end
