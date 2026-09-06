module Kitchen
  # Liste de courses d'une ligne de cuisine (epic #219, phase 6) : pour chaque
  # produit actif paramétré sur son type, la quantité totale pour le nombre de
  # convives.
  #
  # L'arrondi est TOUJOURS vers le haut — mieux vaut acheter un peu trop que pas
  # assez pour un buffet servi le jour même. Il joue deux fois : une fois pour
  # obtenir un nombre entier de pièces, de grammes ou de millilitres, une
  # seconde fois pour condenser l'affichage en kilos ou en litres à une
  # décimale sans jamais annoncer moins que ce qui a été calculé.
  class ShoppingList
    Line = Struct.new(:product, :quantity, :display, keyword_init: true)

    CONDENSE_THRESHOLD = 1000

    def initialize(order)
      @order = order
    end

    def lines
      @lines ||= KitchenProduct.active.for_kind(@order.kind).ordered.map { |product| line_for(product) }
    end

    def empty? = lines.empty?

    private

    def line_for(product)
      quantity = (product.quantity_for(@order.kind) * @order.people).ceil
      Line.new(product: product, quantity: quantity, display: display_for(product.unit, quantity))
    end

    def display_for(unit, quantity)
      case unit
      when "piece" then pieces_display(quantity)
      when "g"     then measured_display(quantity, "g", "kg")
      when "ml"    then measured_display(quantity, "ml", "l")
      end
    end

    def pieces_display(quantity)
      quantity > 1 ? "#{quantity} pièces" : "#{quantity} pièce"
    end

    def measured_display(quantity, small_unit, big_unit)
      return "#{quantity} #{small_unit}" if quantity <= CONDENSE_THRESHOLD

      "#{ceil_to_one_decimal(quantity / 1000.0)} #{big_unit}".tr(".", ",")
    end

    # Arrondit vers le haut à une décimale : 1,04 devient 1,1, jamais 1,0 — un
    # affichage condensé qui annoncerait moins que la quantité réellement
    # calculée reviendrait à faire les courses en dessous du besoin.
    def ceil_to_one_decimal(value)
      (value * 10).ceil / 10.0
    end
  end
end
