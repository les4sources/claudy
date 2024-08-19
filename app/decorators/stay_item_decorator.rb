class StayItemDecorator < ApplicationDecorator
  delegate_all

  def item_name
    object.item&.name
  end

  def item_type
    case object.item_type
    when "experience"
      "Atelier"
    when "lodging"
      "Hébergement"
    when "Product"
      "Produit"
    when "RentalItem"
      "Location"
    when "Space"
      "Espace"
    when "Room"
      "Chambre"
    when "Bed"
      "Lit"
    end
  end
end
