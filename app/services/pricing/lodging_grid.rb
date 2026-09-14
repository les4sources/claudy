module Pricing
  # Classification d'une NUIT d'hébergement (epic #260, décision 1).
  #
  # Une nuit porte la date du soir où l'on se couche : la « nuit du vendredi »
  # est celle du vendredi au samedi. Le site des 4 Sources vend donc :
  #
  #   Nuit semaine  : dimanche, lundi, mardi, mercredi, jeudi.
  #   Nuit week-end : vendredi et samedi.
  #
  # Rien à voir avec `Pricing::HallGrid`, qui classe des JOURNÉES de salle et
  # doit couper le vendredi à 18h30. Une nuit ne se coupe pas en deux : les deux
  # règles sont donc volontairement séparées plutôt que mutualisées.
  module LodgingGrid
    module_function

    FRIDAY   = 5
    SATURDAY = 6

    WEEKEND_NIGHT_WDAYS = [FRIDAY, SATURDAY].freeze

    def weekend_night?(date)
      !date.nil? && WEEKEND_NIGHT_WDAYS.include?(date.wday)
    end

    def weeknight?(date)
      !date.nil? && !weekend_night?(date)
    end

    # La paire du site : nuit du vendredi ET nuit du samedi, consécutives.
    def weekend_pair?(first, second)
      return false if first.nil? || second.nil?

      first.wday == FRIDAY && second == first + 1
    end
  end
end
