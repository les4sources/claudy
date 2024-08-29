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

  def item_info
    case object.item_type
    when StayItem::LODGING, StayItem::ROOM, StayItem::BED 
      date_range
    when StayItem::EXPERIENCE
      %Q(#{l(object.start_date, format: :short) } - #{object.adults_count||0} adulte(s), #{object.children_count||0} enfant(s) - #{object.duration} )
    when StayItem::SPACE
      %Q(#{l(object.start_date, format: :short) } - #{duration} )
    when StayItem::PRODUCT
      %Q(quantité commandée: #{object.quantity})
    when StayItem::RENTAL_ITEM
      %Q(#{object.quantity} x #{(object.end_date-object.start_date).to_i} jour(s))
    end
  end


  # TODO: shared method with stay_decorator --> DRY it
  def date_range
    if object.start_date.year == object.end_date.year
      if object.start_date.month == object.end_date.month && object.start_date.year == Date.today.year
        # Même mois et année en cours
        "du #{object.start_date.day} au #{l(object.end_date, format: :short)}"
      elsif object.start_date.month == object.end_date.month
        # Même mois, mais année différente de l'année en cours
        "du #{object.start_date.day} au #{object.end_date.day} #{l(object.start_date, format: :month_year)}"
      else
        # Mêmes années, mois différents
        "du #{l(object.start_date, format: :short)} au #{object.end_date.day} #{l(object.end_date, format: :month_year)}"
      end
    else
      # Années différentes
      "du #{object.start_date.day} #{l(object.start_date, format: :month_year)} au #{object.end_date.day} #{l(object.end_date, format: :month_year)}"
    end
  end


  def duration
    case object.duration
    when "2h"
      "2 heures"
    when "evening"
      "soirée"
    when "day"
      "journée"
    when "see_notes"
      "voir notes"
    when "fullday"
      "journée + soirée"
    end
  end


end
