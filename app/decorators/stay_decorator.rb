class StayDecorator < ApplicationDecorator
  delegate_all

  def self.collection_decorator_class
    PaginatingDecorator
  end

   def group_or_name
    classes = object.deleted? ? "line-through" : nil
    if object.group_name.presence
      h.content_tag(:span, group_name, class: classes)
    else
      h.content_tag(:span, name, class: classes)
    end
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


  def lodging_badge(font_size: "xs")
    if !object.lodgings.empty?
      shared_classes = "text-#{font_size} font-semibold text-center py-0.5 px-1 rounded"
      case object.lodgings.first.id
      when 1
        if object.confirmed?
          h.content_tag(:span, "Chevêche", class: "#{shared_classes} bg-emerald-100 text-emerald-800")
        else
          h.content_tag(:span, "Chevêche", class: "#{shared_classes} border border-emerald-200 text-emerald-800")
        end
      when 2
        if object.confirmed?
          h.content_tag(:span, "Hulotte", class: "#{shared_classes} bg-emerald-200 text-emerald-800")
        else
          h.content_tag(:span, "Hulotte", class: "#{shared_classes} border border-emerald-200 text-emerald-800")
        end
      when 3
        if object.confirmed?
          h.content_tag(:span, "Grand-Duc", class: "#{shared_classes} bg-emerald-300 text-emerald-800")
        else
          h.content_tag(:span, "Grand-Duc", class: "#{shared_classes} border border-emerald-200 text-emerald-800")
        end
      end
    end
  end 


   def rooms_badges(font_size: "xs")
    rooms = Room.where(id: object.rooms.map(&:id).uniq)
    shared_classes = "text-#{font_size} font-semibold text-center py-0.5 px-1 rounded"
    html = ""
    rooms.each do |room|
      case room.level
      when 0
        if object.confirmed?
          specific_classes = "bg-indigo-100 text-indigo-800"
        else
          specific_classes = "border border-indigo-100 text-indigo-800"
        end
      when 1
        if object.confirmed?
          specific_classes = "bg-purple-100 text-purple-800"
        else
          specific_classes = "border border-purple-100 text-purple-800"
        end
      when 2
        if object.confirmed?
          specific_classes = "bg-pink-100 text-pink-800"
        else
          specific_classes = "border border-pink-100 text-pink-800"
        end
      end
      html << h.content_tag(
        :span, 
        room.code, 
        class: "#{shared_classes} #{specific_classes}", 
        "data-tooltip-target": "tooltip-room-#{room.id}"
      )
    end
    h.raw(html)
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

  def people_emojis
    emojis = []
    if object.adults > 0
      emojis << "#{object.adults} 🧑"
    end
    if object.children > 0
      emojis << "#{object.children} 👨‍👧"
    end
    if (object.babies || 0) > 0
      emojis << "#{object.babies} 🧑‍🍼"
    end
    emojis.join(" ")
  end

  def calendar_class
    classes = ["shadow", "border-l-4"]
    if !object.confirmed?
      classes << ["opacity-50"] 
    end
    if object.lodgings.empty?
      classes << ["border-purple-500", "bg-purple-50"]
    else
      classes << ["border-emerald-500", "bg-emerald-50"]
    end
    classes.join(" ")
  end

   def space_calendar_class
    classes = ["shadow", "border-l-4", "border-l-orange-500", "bg-orange-50"]
    if !object.confirmed?
      classes << ["opacity-50"] 
    end
    classes.join(" ")
  end

  def experience_calendar_class
    classes = ["shadow", "border-l-4", "border-l-green-500", "bg-green-50"]
    if !object.confirmed?
      classes << ["opacity-50"] 
    end
    classes.join(" ")
  end

  def dates_counter(current_date)
    if object.end_date == object.start_date + 1.day
    else
      total_days = (object.end_date - object.start_date).to_i
      if object.start_date == current_date
        "(1/#{total_days})"
      else
        day = (current_date - object.start_date + 1).to_i
        "(#{day}/#{total_days})"
      end
    end
  end

   def payment_status_color
    case object.payment_status
    when "pending"
      "red-200"
    when "partially_paid"
      "yellow-200"
    when "paid"
      "green-200"
    else
      "gray-200"
    end
  end

   def payments_total
    h.content_tag :span,
                  h.number_to_currency(payments.sum(:amount_cents) / 100.0),
                  id: "stay-#{object.id}-payments-sum"
  end


  def total_remaining_amount
    h.number_to_currency(object.total_remaining_amount)
  end

  def total_amount
    h.number_to_currency(object.final_price)
  end

  
  def status
    shared_classes = "text-xs font-medium mr-2 px-2.5 py-0.5 rounded"
    if object.deleted?
      h.content_tag(:span, "Supprimée", class: "#{shared_classes} bg-red-100 text-red-800 dark:bg-red-200 dark:text-red-900")
    else
      case object.status
      when "canceled"
        h.content_tag(:span, "Annulée", class: "#{shared_classes} bg-red-100 text-red-800 dark:bg-red-200 dark:text-red-900")
      when "confirmed"
        h.content_tag(:span, "Confirmée", class: "#{shared_classes} bg-green-100 text-green-800 dark:bg-green-200 dark:text-green-900")
      when "pending"
        h.content_tag(:span, "En attente", class: "#{shared_classes} bg-yellow-100 text-yellow-800 dark:bg-yellow-200 dark:text-yellow-900")
      else
        object.status
      end
    end
  end



  def payment_status
    shared_classes = "stay-#{object.id}-payment-status text-xs font-medium mr-2 px-2.5 py-0.5 rounded"
    case object.payment_status
    when "pending"
      h.content_tag(:span, "Non payée", class: "#{shared_classes} bg-red-200 text-red-800")
    when "partially_paid"
      h.content_tag(:span, "Payée partiellement", class: "#{shared_classes} bg-yellow-200 text-yellow-800")
    when "paid"
      h.content_tag(:span, "Payée", class: "#{shared_classes} bg-green-200 text-green-800")
    else
      if object.payment_status.presence
        h.content_tag(:span, object.payment_status, class: "#{shared_classes} bg-gray-100 text-gray-800")
      end
    end
  end

   def invoice_status
    case object.invoice_status
    when "requested"
      "À fournir"
    when "sent"
      "Envoyée ✔"
    else
      "Non requise"
    end
  end

end
