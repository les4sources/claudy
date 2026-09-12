module Pricing
  # Découpe une suite de nuits dans un gîte en la combinaison de briques la
  # MOINS CHÈRE (epic #260, décision 2 — « on ne paie jamais plus pour moins »).
  #
  # Entrée : les DATES des nuits réservées pour un gîte (une entrée par nuit).
  # Sortie : des `Segment`s — chacun une nuit à l'unité ou un forfait avec sa
  # plage — de quoi écrire une ligne de devis datée et lisible, plus la liste
  # des nuits qu'AUCUNE brique ne sait vendre (`unpriceable`).
  #
  # Les briques, par suite de nuits CONSÉCUTIVES du même gîte :
  #
  #   - la nuit semaine (dimanche → jeudi) à l'unité ;
  #   - la nuit de week-end (vendredi ou samedi) à l'unité, UNIQUEMENT du
  #     15 novembre au 14 mars (décision 1) ;
  #   - le forfait week-end = la paire vendredi + samedi, toute l'année ;
  #   - le forfait 4 nuits = 4 nuits semaine consécutives (lundi → vendredi) ;
  #   - le forfait 6 nuits = 4 nuits semaine + la paire week-end (lundi → dimanche).
  #
  # Hors saison basse, une nuit de vendredi ou de samedi SEULE n'a aucune brique :
  # elle ressort dans `unpriceable`, et c'est ce qui fait refuser la composition
  # au funnel public (décision 3). Le devis, lui, n'invente jamais un prix.
  #
  # Même moteur que `Pricing::HallSchedule` pour les salles : programmation
  # dynamique arrière sur les nuits triées, donc l'optimum global.
  class LodgingSchedule
    # Un morceau du découpage. `brick` nomme la brique retenue.
    Segment = Struct.new(:lodging_name, :brick, :from, :to, :nights, :amount_cents,
                         keyword_init: true) do
      def single_night? = nights == 1
    end

    Result = Struct.new(:segments, :unpriceable, keyword_init: true) do
      def total_cents = segments.sum(&:amount_cents)
      def complete?   = unpriceable.empty?
    end

    # `nights` : les dates des nuits (Date), dans n'importe quel ordre.
    def self.call(lodging_name, nights)
      new(lodging_name, nights).result
    end

    def initialize(lodging_name, nights)
      @name   = lodging_name.to_s
      @nights = Array(nights).compact.uniq.sort
    end

    def result
      return Result.new(segments: [], unpriceable: []) if @nights.empty?

      solve
    end

    private

    # DP arrière : best[i] = [coût, segments, nuits invendables] pour le reste.
    # Une nuit sans brique n'interrompt pas le calcul : elle est mise de côté et
    # comptée pour zéro, pour que le devis reste lisible pendant que le refus se
    # décide ailleurs.
    def solve
      n    = @nights.size
      best = Array.new(n + 1)
      best[n] = [0, [], []]

      (n - 1).downto(0) do |i|
        options = candidates(i).map do |segment, span|
          rest = best[i + span]
          [segment.amount_cents + rest[0], [segment] + rest[1], rest[2]]
        end

        best[i] = options.min_by(&:first) || begin
          rest = best[i + 1]
          [rest[0], rest[1], [@nights[i]] + rest[2]]
        end
      end

      Result.new(segments: best[0][1], unpriceable: best[0][2])
    end

    def candidates(i)
      [single(i), weekend_pair(i), package_4(i), package_6(i)].compact
    end

    # Une nuit à l'unité. Le vendredi et le samedi n'existent à l'unité qu'en
    # saison basse — sinon, pas de candidat du tout.
    def single(i)
      night = @nights[i]
      brick = if Pricing::LodgingGrid.weekend_night?(night)
        Pricing::LodgingSeason.low_season?(night) ? "weekend_night_low_season" : nil
      else
        "weeknight"
      end
      return nil if brick.nil?

      segment(brick, i, 1)
    end

    # La paire vendredi + samedi vaut toujours le forfait, même en saison basse
    # (480 € < 2 × 260 € pour La Chevêche).
    def weekend_pair(i)
      return nil unless run?(i, 2)
      return nil unless Pricing::LodgingGrid.weekend_pair?(@nights[i], @nights[i + 1])

      segment("weekend_2_nights", i, 2)
    end

    # 4 nuits semaine consécutives — le lundi → vendredi du site.
    def package_4(i)
      return nil unless run?(i, 4)
      return nil unless (i...i + 4).all? { |j| Pricing::LodgingGrid.weeknight?(@nights[j]) }

      segment("package_4_nights", i, 4)
    end

    # 4 nuits semaine puis la paire week-end contiguë — le lundi → dimanche.
    def package_6(i)
      return nil unless run?(i, 6)
      return nil unless (i...i + 4).all? { |j| Pricing::LodgingGrid.weeknight?(@nights[j]) }
      return nil unless Pricing::LodgingGrid.weekend_pair?(@nights[i + 4], @nights[i + 5])

      segment("package_6_nights", i, 6)
    end

    def segment(brick, i, span)
      amount = Pricing::Catalog.lodging_brick_cents(@name, brick)
      return nil if amount.nil?

      [Segment.new(lodging_name: @name, brick: brick, from: @nights[i], to: @nights[i + span - 1],
                   nights: span, amount_cents: amount), span]
    end

    # Les `span` nuits à partir de `i` existent et se suivent sans trou.
    def run?(i, span)
      return false if i + span > @nights.size

      (i + 1...i + span).all? { |j| @nights[j] == @nights[j - 1] + 1 }
    end
  end
end
