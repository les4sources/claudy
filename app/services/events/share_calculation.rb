module Events
  # Ce qui revient à qui sur un événement (epic #245, décision 5).
  #
  #   base = recettes encaissées − frais fixes
  #   part organisateurs = base × taux, JAMAIS négative (base ≤ 0 → 0 partout)
  #   part 4 Sources = le reste
  #
  # La répartition entre organisateurs suit les poids, au plus fort reste
  # (`MoneyDistribution`) : la somme des parts vaut EXACTEMENT la part totale,
  # pas « à un centime près ».
  #
  # Ce calcul se rejoue à chaque affichage tant que l'événement n'est pas réglé.
  # Une fois réglé, c'est le `EventSettlement` qui fait foi — ses chiffres sont
  # figés, et `for_settlement` les relit sans jamais recalculer.
  class ShareCalculation
    Line = Struct.new(:human, :weight, :amount_cents, keyword_init: true)

    attr_reader :event, :revenue_cents, :costs_cents, :share_percent

    def self.for_settlement(settlement)
      new(settlement.event).tap { |calc| calc.freeze_to(settlement) }
    end

    def initialize(event)
      @event = event
      @revenue_cents = event.recorded_revenue_cents.to_i
      @costs_cents = event.fixed_costs_cents.to_i
      @share_percent = event.effective_organizer_share_percent.to_i
      @frozen_lines = nil
    end

    # Bascule le calcul sur les chiffres FIGÉS d'un règlement : après règlement,
    # une recette qui arrive ne doit plus rien déplacer à l'écran.
    def freeze_to(settlement)
      @revenue_cents = settlement.revenue_cents
      @costs_cents = settlement.costs_cents
      @share_percent = settlement.organizer_share_percent
      @base_cents = settlement.base_cents
      @organizers_cents = settlement.organizers_cents
      @house_cents = settlement.house_cents
      @frozen_lines = settlement.event_settlement_lines.includes(:human).map do |line|
        Line.new(human: line.human, weight: line.weight, amount_cents: line.amount_cents)
      end
      self
    end

    def base_cents
      @base_cents ||= revenue_cents - costs_cents
    end

    # Une base négative ne se partage pas : on ne fait pas payer les organisateurs
    # pour un événement déficitaire. Le déficit reste à la maison.
    def organizers_cents
      @organizers_cents ||= base_cents.positive? ? (base_cents * share_percent / 100.0).round : 0
    end

    def house_cents
      @house_cents ||= base_cents - organizers_cents
    end

    def lines
      @lines ||= @frozen_lines || build_lines
    end

    def lines_total_cents = lines.sum(&:amount_cents)

    private

    def build_lines
      organizers = event.event_organizers.includes(:human).sort_by { |o| [o.human.name.to_s, o.id] }
      return [] if organizers.empty?

      weights = organizers.map { |o| o.weight.to_i }
      amounts = MoneyDistribution.distribute_cents(organizers_cents, weights)

      organizers.each_with_index.map do |organizer, index|
        Line.new(human: organizer.human, weight: organizer.weight, amount_cents: amounts[index])
      end
    end
  end
end
