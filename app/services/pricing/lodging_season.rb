module Pricing
  # Saison basse des gîtes (epic #260, décision 1) : **du 15 novembre au 14 mars
  # inclus**. C'est la seule période où le site vend une nuit de week-end à
  # l'unité — le reste de l'année, le week-end se loue par paire.
  #
  # La saison s'évalue NUIT PAR NUIT, sur la date de chaque nuit : un séjour à
  # cheval sur le 14 mars a des nuits des deux côtés, et c'est voulu.
  module LodgingSeason
    module_function

    # Bornes stockées en (mois, jour) : la période enjambe le Nouvel An, donc
    # elle ne peut pas s'écrire comme un intervalle de dates d'une seule année.
    LOW_SEASON_FROM = [11, 15].freeze # 15 novembre
    LOW_SEASON_TO   = [3, 14].freeze  # 14 mars

    def low_season?(date)
      return false if date.nil?

      # `Array#<=>` compare élément par élément : (mois, jour) se range donc
      # dans l'ordre du calendrier sans se soucier de l'année.
      today = [date.month, date.day]

      (today <=> LOW_SEASON_FROM) >= 0 || (today <=> LOW_SEASON_TO) <= 0
    end

    def high_season?(date) = !date.nil? && !low_season?(date)
  end
end
