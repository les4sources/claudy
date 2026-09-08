module Pricing
  # Classification semaine / week-end d'une occupation de salle (epic #234,
  # décision 4). La page tarifs du site ouvre le week-end le **vendredi à
  # 18h30** : la JOURNÉE du vendredi appartient donc encore à la grille semaine,
  # sa SOIRÉE au week-end.
  #
  #   Semaine  : journée du lundi au vendredi, soirée du lundi au jeudi.
  #   Week-end : soirée du vendredi, samedi et dimanche (journée et soirée).
  #
  # Le seul cas que la décision 4 ne tranche pas est « journée + soirée » un
  # vendredi, qui chevauche les deux grilles. Il ne bascule PAS en week-end
  # plein : la journée reste en semaine et la soirée s'ajoute au « forfait
  # soir » week-end (`straddles_weekend?`, tranché le 2026-09-08 pour rester
  # cohérent avec les soirées posées sur un forfait de journées).
  module HallGrid
    module_function

    WEEKEND_WDAYS = [6, 0].freeze # samedi, dimanche
    FRIDAY = 5

    # Grille d'une occupation (date + période).
    def weekend?(date, period)
      return false if date.nil?
      return true  if WEEKEND_WDAYS.include?(date.wday)

      date.wday == FRIDAY && period.to_s != "journee"
    end

    # « Journée + soirée » un vendredi : à cheval sur les deux grilles.
    def straddles_weekend?(date, period)
      !date.nil? && date.wday == FRIDAY && period.to_s == "journee_et_soiree"
    end

    # Grille de la JOURNÉE d'une date — celle qui décide des forfaits
    # multi-jours, qui ne portent que des journées.
    def weekend_day?(date)
      return false if date.nil?

      WEEKEND_WDAYS.include?(date.wday)
    end

    # Grille de la SOIRÉE d'une date, pour le « forfait soir » ajouté par-dessus
    # un forfait multi-jours.
    def weekend_evening?(date)
      return false if date.nil?

      WEEKEND_WDAYS.include?(date.wday) || date.wday == FRIDAY
    end

    def weekday?(date)
      !date.nil? && (1..5).cover?(date.wday)
    end
  end
end
