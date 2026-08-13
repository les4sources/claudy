module Catalog
  # PROPOSE les prix sourcier et public d'un palier (issue #157).
  #
  # Ce service ne décide de rien : il préremplit un formulaire. Ce qui est
  # enregistré est la valeur du champ, pas le résultat de ce calcul — c'est
  # exactement ce qui empêche une correction rétroactive de coefficient de
  # déplacer un prix déjà appliqué.
  #
  # Deux règles, de sens opposé :
  #
  #   bar     : sourcier = ACHAT × bar.member_markup      (1,91 € → 2,10 €)
  #             le prix public est saisi à la main (4,00 €), jamais dérivé
  #   cellier : sourcier = RÉFÉRENCE × grocery.member_ratio (2,95 € → 2,80 €)
  #             public   = RÉFÉRENCE × grocery.public_ratio (2,95 € → 3,10 €)
  #
  # Les coefficients vivent dans `rates` (clés seedées en #156) et sont lus À LA
  # DATE du palier : proposer un palier de mars 2024 doit utiliser la majoration
  # de mars 2024.
  class BuildPrice < ServiceBase
    DEFAULT_BAR_MARKUP = 1.10
    DEFAULT_GROCERY_MEMBER_RATIO = 0.95
    DEFAULT_GROCERY_PUBLIC_RATIO = 1.05

    Proposal = Struct.new(:member_price_cents, :public_price_cents, keyword_init: true)

    def initialize(channel:, purchase_price_cents: nil, reference_price_cents: nil, on: Date.current)
      @channel = channel.to_s
      @purchase_price_cents = purchase_price_cents
      @reference_price_cents = reference_price_cents
      @on = on || Date.current
    end

    def run
      catch_error(context: { channel: @channel, on: @on }) { build }
    end

    def run!
      build
    end

    private

    def build
      case @channel
      when "bar" then bar_proposal
      when "grocery" then grocery_proposal
      else Proposal.new(member_price_cents: nil, public_price_cents: nil)
      end
    end

    # Au bar, seul le prix sourcier se déduit — du prix d'ACHAT. Le prix public
    # est une décision commerciale (4,00 € pour une bière achetée 1,91 €), pas
    # un multiple de l'achat : on ne le propose pas.
    def bar_proposal
      Proposal.new(
        member_price_cents: apply(@purchase_price_cents, rate("bar.member_markup", DEFAULT_BAR_MARKUP)),
        public_price_cents: nil
      )
    end

    def grocery_proposal
      Proposal.new(
        member_price_cents: apply(@reference_price_cents, rate("grocery.member_ratio", DEFAULT_GROCERY_MEMBER_RATIO)),
        public_price_cents: apply(@reference_price_cents, rate("grocery.public_ratio", DEFAULT_GROCERY_PUBLIC_RATIO))
      )
    end

    def apply(cents, coefficient)
      return nil if cents.blank? || coefficient.nil?

      (cents.to_i * coefficient).round
    end

    # Les clés sourcières sont stockées en unité `percent` : 110 signifie 1,10.
    # `Pricing::Rates` n'expose pas encore de lecture datée en pourcentage, donc
    # on convertit ici — un cent absent retombe sur la constante documentée.
    def rate(key, fallback)
      value = Pricing::Rates.cents(key, on: @on)
      value.nil? ? fallback : value / 100.0
    end
  end
end
