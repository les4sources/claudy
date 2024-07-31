class StayDecorator < ApplicationDecorator
  delegate_all

  def self.collection_decorator_class
    PaginatingDecorator
  end


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


   def tr_class
    if 1==0#object.deleted?
      "bg-stone-50 opacity-50"
    elsif object.confirmed?
      "bg-white"
    elsif object.declined?
      "bg-red-50 opacity-75"
    else
      "bg-yellow-50 opacity-75"
    end
  end

  def tr_border_class
    classes = ["border-l-8"]
    if object.customer.nil?
      classes << ["border-teal-500"]
    else
      classes << ["border-orange-500"]
    end
    classes.join(" ")
  end

  def status_emoji
    case object.status
    when "canceled"
      h.content_tag(:span, "❌", data: { "tooltip-target": "tooltip-status-canceled" })
    when "confirmed"
      h.content_tag(:span, "✅", data: { "tooltip-target": "tooltip-status-confirmed" })
    when "pending"
      h.content_tag(:span, "⏳", data: { "tooltip-target": "tooltip-status-pending" })
    when "declined"
      h.content_tag(:span, "🙅‍♀️", data: { "tooltip-target": "tooltip-status-declined" })
    else
      object.status
    end
  end

end
