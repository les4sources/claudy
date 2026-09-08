module Kitchen
  # La remise de formule trio (issue #238, décisions 4 et 5).
  #
  # Depuis que le goûter est un service facturable à part, une journée complète
  # coûte 15 + 7 + 15 = 37 € par personne. La formule trio ramène cette journée
  # au prix annoncé au client, 35 € — et reste donc ce qu'elle a toujours été :
  # une REMISE, pas un type de prestation.
  #
  # Elle se forme quand, pour un même séjour et un même jour, trois lignes
  # facturables de la famille `repas` couvrent midi, goûter et soir. Elle saute
  # dès qu'une des trois tombe — refus de la cuisine, annulation client — et se
  # reforme quand la ligne manquante revient.
  #
  # La remise est ABSORBÉE PAR LE GOÛTER : midi et soir gardent leur tarif
  # plein, le goûter porte le reste (5 € avec les tarifs actuels). Le prix du
  # goûter reste ainsi explicable au client, ligne par ligne.
  #
  # Rien n'est stocké : `price_cents` est réécrit par `update_columns`, sans
  # callbacks — c'est une valeur dérivée, pas une modification de la demande.
  # Sans ça, chaque recalcul renverrait un email à la cuisine.
  class TrioDiscount
    MOMENTS = %w[midi gouter soir].freeze

    def initialize(stay:, date:)
      @stay = stay
      @date = date
    end

    # Recalcule les trois lignes du jour : au prix de formule si elle se forme,
    # au tarif plein sinon.
    def apply!
      return if @stay.blank? || @date.blank?

      lines = lines_by_moment
      return reset_all(lines.values) unless forms_trio?(lines)

      apply_discount(lines)
    end

    # Sert aussi à l'affichage : une ligne mentionne « formule trio » quand son
    # jour en forme une.
    def forms_trio?(lines = lines_by_moment)
      return false unless MOMENTS.all? { |moment| lines[moment].present? }
      # Une remise s'applique à une journée COHÉRENTE : trois services pour le
      # même nombre de convives. Sinon chaque ligne reste au tarif plein.
      return false unless lines.values.map(&:people).uniq.size == 1
      # Un prix unitaire forcé à la main n'est jamais écrasé : c'est un
      # arbitrage humain, pas une valeur à recalculer.
      return false if lines.values.any? { |line| line.unit_price_cents.present? }

      trio_rate_cents.present?
    end

    private

    # Une ligne par moment. Les buffets et apéros posés le même jour n'entrent
    # pas dans la formule : elle ne concerne que la famille `repas`
    # (`gouter` en fait partie).
    def lines_by_moment
      scope = @stay.meal_orders.billable.of_family("repas").where(date: @date)

      scope.each_with_object({}) do |line, by_moment|
        moment = line_moment(line)
        next unless MOMENTS.include?(moment)

        by_moment[moment] ||= line
      end
    end

    # Le goûter porte son moment dans son TYPE : une ligne `gouter` compte comme
    # le service du goûter, quel que soit le champ `moment`.
    def line_moment(line)
      return "gouter" if line.kind == "gouter"

      line.moment.to_s
    end

    def trio_rate_cents = Pricing::Catalog.meal_per_person_cents("trio")

    def apply_discount(lines)
      people = lines["midi"].people.to_i
      full_day = lines["midi"].unit_price_effective_cents + lines["soir"].unit_price_effective_cents
      gouter_cents = (trio_rate_cents * people) - (full_day * people)

      write(lines["midi"], lines["midi"].unit_price_effective_cents * people)
      write(lines["soir"], lines["soir"].unit_price_effective_cents * people)
      # Jamais négatif : si midi + soir dépassaient déjà le prix de formule, le
      # goûter serait offert, pas facturé à rebours.
      write(lines["gouter"], [gouter_cents, 0].max)
    end

    def reset_all(lines)
      lines.each { |line| write(line, line.unit_price_effective_cents * line.people.to_i) }
    end

    # `update_columns` : pas de callbacks, donc pas de notification à la cuisine
    # et pas de récursion — le recalcul n'est pas une modification de la demande.
    def write(line, cents)
      return if line.price_cents == cents

      line.update_columns(price_cents: cents, updated_at: Time.current)
    end
  end
end
