module Consignments
  # Un produit que l'artisan gère lui-même depuis son espace (epic #359, phase 2,
  # décision 7) : un article `craft` du catalogue, rattaché à lui, avec UN prix.
  #
  # Le prix vit dans les paliers datés (`CatalogPrice`) comme tout le catalogue :
  # le changer ne réécrit jamais le passé. Le palier en cours est clôturé la
  # veille et un nouveau démarre aujourd'hui — sauf s'il a démarré aujourd'hui
  # même, auquel cas on le corrige en place (un palier d'un jour qui finirait la
  # veille de son début n'a pas de sens).
  #
  # Le prix de vente est le prix PUBLIC (ce que le client paie en rayon) ; le
  # prix habitant vaut le même par défaut, pour l'encodage du cahier des
  # habitants. La commission, elle, se lit sur le contrat, jamais ici.
  class SaveProduct < ServiceBase
    attr_reader :product

    def initialize(consignor:, product: nil, on: Date.current)
      @consignor = consignor
      @product = product || consignor.catalog_items.craft.new
      @on = on
      @report_errors = false
    end

    def run(name:, unit:, price_euros:)
      catch_error(context: { consignor_id: @consignor.id, product_id: @product.id }) do
        run!(name: name, unit: unit, price_euros: price_euros)
      end
    end

    def run!(name:, unit:, price_euros:)
      price_cents = parse_cents(price_euros)
      raise ServiceError, "Indiquez un prix de vente." if price_cents.nil?
      raise ServiceError, "Le prix ne peut pas être négatif." if price_cents.negative?

      CatalogItem.transaction do
        @product.assign_attributes(name: name.to_s.strip, unit: unit.presence || "piece",
                                   channel: CatalogItem::CRAFT_CHANNEL, consignor: @consignor)
        @product.active = true if @product.new_record?
        raise ServiceError, validation_errors_for(@product) unless @product.save

        apply_price!(price_cents)
      end
      true
    end

    private

    def apply_price!(price_cents)
      current = @product.catalog_prices.covering(@on).first
      return if current && current.public_price_cents == price_cents

      if current&.active_from == @on
        current.update!(public_price_cents: price_cents, member_price_cents: price_cents)
        return
      end

      until_date = current&.active_until
      current&.update!(active_until: @on - 1)
      tier = @product.catalog_prices.new(active_from: @on, active_until: until_date,
                                         public_price_cents: price_cents, member_price_cents: price_cents)
      raise ServiceError, validation_errors_for(tier) unless tier.save
    end

    # « 4,50 » comme « 4.50 » : on tape la virgule au téléphone.
    def parse_cents(value)
      normalized = value.to_s.strip.tr(",", ".")
      return nil if normalized.blank?
      return nil unless normalized.match?(/\A-?\d+(\.\d{1,2})?\z/)

      (BigDecimal(normalized) * 100).round.to_i
    end
  end
end
