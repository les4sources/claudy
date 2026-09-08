module Pricing
  # Découpe l'occupation datée d'un espace en la combinaison de forfaits la
  # MOINS CHÈRE (epic #234, décision 5 — « on ne paie jamais plus pour moins »).
  #
  # Entrée : des occupations `{ key:, date:, period: }` (une par jour et par
  # espace, périodes « journee » / « soiree » / « journee_et_soiree »).
  # Sortie : des `Segment`s, chacun soit un jour à l'unité, soit un forfait avec
  # sa plage de dates — de quoi écrire une ligne de devis lisible.
  #
  # Les candidats, par suite de jours CONSÉCUTIFS d'un même espace :
  #
  #   - le jour à l'unité, au tarif de sa période dans la grille de son jour ;
  #   - le forfait « 2 jours », sur deux jours consécutifs de la MÊME grille ;
  #   - le forfait « 5 jours », dès 3 jours consécutifs entre lundi et vendredi ;
  #   - le forfait week-end « vendredi 18h30 → dimanche soir », qui exige au
  #     minimum la soirée du vendredi, le samedi journée + soirée et la journée
  #     du dimanche.
  #
  # Les forfaits multi-jours ne portent que des JOURNÉES : une soirée posée sur
  # un jour couvert par un forfait s'ajoute au « forfait soir » de la grille de
  # ce soir-là (`Pricing::Catalog.hall_evening_supplement_cents`).
  #
  # La recherche est une programmation dynamique sur les jours triés : chaque
  # position retient le coût minimal du reste, donc l'optimum global.
  class HallSchedule
    DAY_PERIODS     = %w[journee journee_et_soiree].freeze
    EVENING_PERIODS = %w[soiree journee_et_soiree].freeze

    # Un morceau du découpage. `package` est nil pour un jour à l'unité.
    Segment = Struct.new(:key, :package, :from, :to, :period, :evenings, :amount_cents,
                         keyword_init: true) do
      def single_day? = package.nil?
    end

    # Occupations d'UN espace → segments. `occupations` : [{date:, period:}].
    def self.segments_for(key, occupations)
      new(key, occupations).segments
    end

    def initialize(key, occupations)
      @key  = key.to_s
      @days = occupations
        .select { |o| o[:date].present? && o[:period].present? }
        .sort_by { |o| o[:date] }
    end

    def segments
      return [] if @days.empty?

      solve.last
    end

    private

    # DP arrière : best[i] = [coût du reste à partir de i, segments].
    def solve
      n    = @days.size
      best = Array.new(n + 1)
      best[n] = [0, []]

      (n - 1).downto(0) do |i|
        options = candidates(i).map do |segment, span|
          [segment.amount_cents + best[i + span].first, [segment] + best[i + span].last]
        end
        # Aucun candidat : période inconnue du catalogue — le jour est ignoré,
        # comme le faisait déjà `slot_space_entries` avec son `next if unit.nil?`.
        best[i] = options.min_by(&:first) || best[i + 1]
      end

      best[0]
    end

    # Les découpages possibles à partir du jour `i`, en [segment, jours consommés].
    def candidates(i)
      ([single(i), two_days(i), weekend(i)] + five_days(i)).compact
    end

    def single(i)
      day    = @days[i]
      amount = if Pricing::HallGrid.straddles_weekend?(day[:date], day[:period])
        # Journée + soirée un VENDREDI : la journée est en semaine, la soirée
        # au week-end (le site ouvre le week-end à 18h30). On facture donc la
        # journée semaine plus le « forfait soir » de la grille week-end — la
        # même règle que pour une soirée posée par-dessus un forfait de journées
        # (`package`), et jamais plus cher que la journée week-end entière.
        day_amount = Pricing::Catalog.hall_rate_cents(@key, "journee", weekend: false)
        day_amount.nil? ? nil : day_amount + Pricing::Catalog.hall_evening_supplement_cents(@key, weekend: true)
      else
        Pricing::Catalog.hall_rate_cents(
          @key, day[:period], weekend: Pricing::HallGrid.weekend?(day[:date], day[:period])
        )
      end
      return nil if amount.nil?

      [Segment.new(key: @key, package: nil, from: day[:date], to: day[:date],
                   period: day[:period].to_s, evenings: 0, amount_cents: amount), 1]
    end

    def two_days(i)
      return nil unless run?(i, 2) && (i...i + 2).all? { |j| day?(@days[j]) }

      grid = Pricing::HallGrid.weekend_day?(@days[i][:date])
      return nil unless grid == Pricing::HallGrid.weekend_day?(@days[i + 1][:date])

      package(i, 2, "deux_jours", grid)
    end

    # « 5 jours » : la semaine complète du site, retenue dès 3 jours consécutifs
    # entre lundi et vendredi — le DP ne la garde que si elle est moins chère.
    def five_days(i)
      (3..5).filter_map do |span|
        next unless run?(i, span)
        next unless (i...i + span).all? { |j| day?(@days[j]) && Pricing::HallGrid.weekday?(@days[j][:date]) }

        package(i, span, "cinq_jours", false)
      end
    end

    # « Du vendredi 18h30 au dimanche soir » : soirée du vendredi, samedi entier,
    # journée du dimanche au minimum. La soirée du dimanche est comprise.
    def weekend(i)
      return nil unless run?(i, 3)

      friday, saturday, sunday = @days[i], @days[i + 1], @days[i + 2]
      return nil unless friday[:date].wday == Pricing::HallGrid::FRIDAY
      return nil unless evening?(friday) && day?(saturday) && evening?(saturday) && day?(sunday)

      amount = Pricing::Catalog.hall_package_cents(@key, "forfait_weekend", weekend: true)
      return nil if amount.nil?

      # Le forfait ouvre à 18h30 : une journée du vendredi s'ajoute au tarif
      # semaine, elle n'est pas couverte.
      amount += Pricing::Catalog.hall_rate_cents(@key, "journee", weekend: false).to_i if day?(friday)

      [Segment.new(key: @key, package: "forfait_weekend", from: friday[:date], to: sunday[:date],
                   period: "journee", evenings: 0, amount_cents: amount), 3]
    end

    # Un forfait de journées + le « forfait soir » des soirées qu'il ne couvre pas.
    def package(i, span, name, grid)
      base = Pricing::Catalog.hall_package_cents(@key, name, weekend: grid)
      return nil if base.nil?

      covered  = @days[i, span]
      evenings = covered.select { |d| evening?(d) }
      base += evenings.sum do |d|
        Pricing::Catalog.hall_evening_supplement_cents(
          @key, weekend: Pricing::HallGrid.weekend_evening?(d[:date])
        )
      end

      [Segment.new(key: @key, package: name, from: covered.first[:date], to: covered.last[:date],
                   period: "journee", evenings: evenings.size, amount_cents: base), span]
    end

    # Les `span` jours à partir de `i` existent et se suivent sans trou.
    def run?(i, span)
      return false if i + span > @days.size

      (i + 1...i + span).all? { |j| @days[j][:date] == @days[j - 1][:date] + 1 }
    end

    def day?(occupation)     = DAY_PERIODS.include?(occupation[:period].to_s)
    def evening?(occupation) = EVENING_PERIODS.include?(occupation[:period].to_s)
  end
end
