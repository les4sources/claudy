module Catalog
  # Calcule le prix sourcier d'un palier à partir du prix d'achat et d'une MARGE
  # paramétrée par canal (Michael, 2026-08-13).
  #
  #     prix sourcier = prix d'achat × (1 + marge / 100)
  #
  # Une seule notion, trois valeurs — bar, cellier, repas — éditables dans
  # Paramètres > Tarifs sans redéploiement. C'est ce qui rend le prix sourcier
  # AUTOMATIQUE : on saisit ce qu'on lit sur la facture du fournisseur, le reste
  # suit.
  #
  # Le résultat reste STOCKÉ sur le palier, jamais recalculé à la lecture :
  # relever la marge demain ne doit pas déplacer un décompte déjà émis. Et il
  # reste modifiable à la main — ce qui est enregistré est la valeur du champ.
  #
  # La marge est lue À LA DATE du palier : reconstituer un palier de 2024 doit
  # utiliser la marge de 2024, pas celle d'aujourd'hui.
  #
  # Le prix PUBLIC n'est pas une marge : au bar c'est une décision commerciale
  # (4,00 € pour une bière achetée 1,91 €), au cellier il se propose encore
  # depuis le prix de référence quand il y en a un. On ne le fixe jamais d'office.
  class BuildPrice < ServiceBase
    # Marges de repli, utilisées seulement si la clé n'est pas paramétrée.
    DEFAULT_MARGINS = { "bar" => 10, "grocery" => 17, "meal" => 0 }.freeze
    DEFAULT_GROCERY_PUBLIC_RATIO = 1.05

    Proposal = Struct.new(:member_price_cents, :public_price_cents, keyword_init: true)

    def self.margin_key(channel) = "catalog.margin.#{channel}"

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

    # Le prix sourcier seul — ce que le contrôleur applique quand le champ est
    # laissé vide. `nil` quand il n'y a pas de prix d'achat : on ne devine pas.
    def member_price_cents
      return nil if @purchase_price_cents.blank?

      (@purchase_price_cents.to_i * (1 + margin_percent / 100.0)).round
    end

    private

    def build
      Proposal.new(member_price_cents: member_price_cents, public_price_cents: public_proposal)
    end

    # Marge du canal, en pourcentage (10 = +10 %).
    def margin_percent
      configured = Pricing::Rates.cents(self.class.margin_key(@channel), on: @on)
      configured || DEFAULT_MARGINS.fetch(@channel, 0)
    end

    def public_proposal
      return nil unless @channel == "grocery" && @reference_price_cents.present?

      ratio = Pricing::Rates.cents("grocery.public_ratio", on: @on)
      coefficient = ratio.nil? ? DEFAULT_GROCERY_PUBLIC_RATIO : ratio / 100.0

      (@reference_price_cents.to_i * coefficient).round
    end
  end
end
