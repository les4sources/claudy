module Pricing
  # Barème d'un hébergement : prix première nuit + prix nuits suivantes
  # (formule fermée dégressive), plus d'éventuels forfaits nommés qui écrasent
  # la formule pour une durée précise (Q3 hybride).
  #
  #   prix = first_night_cents + (n - 1) * extra_night_cents
  #
  # `named_packages` : { nights => { label:, amount_cents: } }. Quand un séjour
  # tombe exactement sur l'une de ces durées, le forfait nommé remplace le
  # résultat de la formule (override).
  #
  # Tous les montants sont en cents et TVAC.
  class LodgingRate
    attr_reader :name, :first_night_cents, :extra_night_cents, :named_packages

    def initialize(name:, first_night_cents:, extra_night_cents:, named_packages: {})
      @name = name
      @first_night_cents = first_night_cents
      @extra_night_cents = extra_night_cents
      @named_packages = named_packages
    end

    # Renvoie un Hash { label:, amount_cents:, nights: } pour `nights` nuits.
    # Un forfait nommé override la formule s'il existe pour cette durée.
    def quote_for(nights)
      raise ArgumentError, "nights doit être >= 1 (reçu #{nights.inspect})" if nights.to_i < 1

      nights = nights.to_i
      if (package = named_packages[nights])
        { label: "#{name} — #{package[:label]} (#{nights} nuits)",
          amount_cents: package[:amount_cents],
          nights: nights }
      else
        { label: "#{name} — #{nights} #{nights > 1 ? 'nuits' : 'nuit'}",
          amount_cents: formula_amount_cents(nights),
          nights: nights }
      end
    end

    def formula_amount_cents(nights)
      first_night_cents + (nights - 1) * extra_night_cents
    end
  end
end
