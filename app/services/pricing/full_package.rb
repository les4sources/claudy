module Pricing
  # « LA TOTALE » (epic #260, phase 3) : Le Grand-Duc toutes les nuits du séjour
  # **plus** les deux salles et la cuisine pro tous les jours, du jour d'arrivée
  # au jour de départ inclus. Le site la vend comme un forfait par nuit, pas
  # comme une addition de lignes.
  #
  # La détection est STRUCTURELLE, pas tarifaire : si la composition est celle de
  # la totale, c'est le prix de la totale — on ne compare pas avec le prix à
  # l'unité pour prendre le moins cher. C'est ce que dit l'epic.
  #
  # La saison de la totale n'est PAS celle de `Pricing::LodgingSeason` : l'epic
  # pose basse saison du 15 novembre au **15 mars** (contre le 14 mars des
  # gîtes à l'unité) et fait basculer les congés de Noël en haute saison. D'où un
  # module de saison à part plutôt qu'une réutilisation qui masquerait l'écart.
  module FullPackage
    module_function

    LODGING_NAME = "Le Grand-Duc".freeze
    REQUIRED_SPACES = %w[grande_salle petite_salle cuisine_pro].freeze

    # Deux nuits minimum : une nuit isolée reste au prix à l'unité.
    MINIMUM_NIGHTS = 2

    # Remises par paliers, du plus généreux au moins généreux. « à partir de 6 »
    # vaut aussi au-delà.
    DISCOUNTS = [[6, 25], [3, 10]].freeze

    FALLBACK_CENTS = {
      "low_season.weeknight"      =>  89_000, # 890 €
      "low_season.weekend_night"  => 105_000, # 1 050 €
      "high_season.weeknight"     => 101_000, # 1 010 €
      "high_season.weekend_night" => 122_000  # 1 220 €
    }.freeze

    # Congés de Noël de la Fédération Wallonie-Bruxelles, par année scolaire.
    # Une nuit qui y tombe vaut le tarif HAUTE saison même en plein hiver.
    # Constante datée : une nouvelle année scolaire s'ajoute ici.
    CHRISTMAS_HOLIDAYS = [
      Date.new(2026, 12, 19)..Date.new(2027, 1, 3)
    ].freeze

    # Basse saison de la totale : du 15 novembre au 15 mars, congés de Noël
    # exceptés. Bornes en (mois, jour) parce que la période enjambe le Nouvel An.
    LOW_SEASON_FROM = [11, 15].freeze
    LOW_SEASON_TO   = [3, 15].freeze

    def christmas?(date)
      CHRISTMAS_HOLIDAYS.any? { |range| range.cover?(date) }
    end

    def low_season?(date)
      return false if date.nil? || christmas?(date)

      today = [date.month, date.day]
      (today <=> LOW_SEASON_FROM) >= 0 || (today <=> LOW_SEASON_TO) <= 0
    end

    def high_season?(date) = !date.nil? && !low_season?(date)

    # Une nuit de WEEK-END est une nuit qui COMMENCE un vendredi ou un samedi.
    def weekend_night?(date) = !date.nil? && [5, 6].include?(date.wday)

    def rate_key(date)
      season = low_season?(date) ? "low_season" : "high_season"
      "#{season}.#{weekend_night?(date) ? 'weekend_night' : 'weeknight'}"
    end

    def night_cents(date)
      key = rate_key(date)
      Pricing::Rates.cents_or("full_package.#{key}", FALLBACK_CENTS.fetch(key))
    end

    def discount_percent(night_count)
      DISCOUNTS.each { |threshold, percent| return percent if night_count >= threshold }
      0
    end

    # Le devis de la totale pour une liste de dates de nuits.
    Quote = Struct.new(:dates, :gross_cents, :discount_percent, :amount_cents, keyword_init: true) do
      def nights = dates.size
      def discounted? = discount_percent.to_i.positive?
      def seasons = dates.map { |d| Pricing::FullPackage.low_season?(d) ? :low : :high }.uniq
      def single_season = seasons.size == 1 ? seasons.first : nil
    end

    def quote(dates)
      dates = Array(dates).compact.sort
      gross = dates.sum { |date| night_cents(date) }
      percent = discount_percent(dates.size)
      # Remise appliquée sur la SOMME des nuits, arrondie au cent.
      amount = (gross * (100 - percent) / 100.0).round

      Quote.new(dates: dates, gross_cents: gross, discount_percent: percent, amount_cents: amount)
    end

    # La composition est-elle celle de la totale ?
    #
    #   nights            : [dates des nuits du Grand-Duc]
    #   other_lodgings?   : un autre gîte est sélectionné une nuit quelconque
    #   stay_days         : [dates du séjour, arrivée → départ INCLUS]
    #   occupied_spaces   : { "grande_salle" => Set[dates], ... }
    def applies?(nights:, other_lodgings:, stay_days:, occupied_spaces:)
      return false if other_lodgings
      return false if nights.size < MINIMUM_NIGHTS
      return false if stay_days.blank?
      # Toutes les nuits du séjour au Grand-Duc : autant de nuits que de jours
      # moins un, et pas une de moins.
      return false unless nights.size == stay_days.size - 1

      REQUIRED_SPACES.all? do |space|
        occupied = occupied_spaces[space]
        occupied.present? && stay_days.all? { |day| occupied.include?(day) }
      end
    end

    def label(quote)
      parts = ["La totale — Le Grand-Duc + les 2 salles + cuisine pro",
               "#{quote.nights} nuit#{'s' if quote.nights > 1}"]
      parts << season_label(quote)
      parts << "−#{quote.discount_percent} %" if quote.discounted?
      parts.compact.join(", ")
    end

    def season_label(quote)
      case quote.single_season
      when :low  then "basse saison"
      when :high then "haute saison"
      else "saisons mêlées"
      end
    end
  end
end
