class StayItemDecorator < ApplicationDecorator
  delegate_all

  def item_name
    object.item&.name
  end

  def item_type
    case object.item_type
    when StayItem::EXPERIENCE
      "Atelier"
    when StayItem::LODGING
      "Hébergement"
    when StayItem::PRODUCT
      "Produit"
    when StayItem::RENTAL_ITEM
      "Location"
    when StayItem::SPACE
      "Espace"
    when StayItem::ROOM
      "Chambre"
    when StayItem::BED
      "Lit"
    end
  end

  def start_date(format: :long)
    l(object.start_date, format: format)
  end

  def end_date(format: :long)
    l(object.end_date, format: format)
  end

end
