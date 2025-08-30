class BookingDecorator < ApplicationDecorator
  delegate_all

  def self.collection_decorator_class
    PaginatingDecorator
  end

  def babies
    (object.babies || 0) > 0 ? object.babies : "aucun"
  end

  def children
    (object.children || 0) > 0 ? object.children : "aucun"
  end

  def bedsheets
    object.bedsheets? ? "OUI" : "non"
  end

  def calendar_class
    classes = ["shadow", "border-l-4"]
    if !object.confirmed?
      classes << ["opacity-50"] 
    end
    if object.lodging.nil?
      classes << ["border-purple-500", "bg-purple-50"]
    else
      classes << ["border-emerald-500", "bg-emerald-50"]
    end
    classes.join(" ")
  end

  def dates_counter(current_date)
    if object.to_date == object.from_date + 1.day
    else
      total_days = (object.to_date - object.from_date).to_i
      if object.from_date == current_date
        "(1/#{total_days})"
      else
        day = (current_date - object.from_date + 1).to_i
        "(#{day}/#{total_days})"
      end
    end
  end

  def date_range
    if object.from_date.year == object.to_date.year
      if object.from_date.month == object.to_date.month && object.from_date.year == Date.today.year
        # Même mois et année en cours
        "du #{object.from_date.day} au #{l(object.to_date, format: :short)}"
      elsif object.from_date.month == object.to_date.month
        # Même mois, mais année différente de l'année en cours
        "du #{object.from_date.day} au #{object.to_date.day} #{l(object.from_date, format: :month_year)}"
      else
        # Mêmes années, mois différents
        "du #{l(object.from_date, format: :short)} au #{object.to_date.day} #{l(object.to_date, format: :month_year)}"
      end
    else
      # Années différentes
      "du #{object.from_date.day} #{l(object.from_date, format: :month_year)} au #{object.to_date.day} #{l(object.to_date, format: :month_year)}"
    end
  end

  def email
    object.email.present? ? h.mail_to(object.email, object.email, class: "text-blue-500 border-b-2 border-blue-200 hover:text-blue-700 focus:text-blue-700") : "-"
  end

  def from_date(format: :short)
    l(object.from_date, format: format)
  end

  def group_or_name
    classes = object.deleted? ? "line-through" : nil
    if object.group_name.presence
      h.content_tag(:span, group_name, class: classes)
    else
      h.content_tag(:span, name, class: classes)
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

  def label_bedsheets
    return if !object.bedsheets?
    h.content_tag(:span, "draps", class: "secondary label")
  end

  def label_towels
    return if !object.towels?
    h.content_tag(:span, "essuies", class: "secondary label")
  end

  def lodging_badge(font_size: "xs")
    if !object.lodging.nil?
      shared_classes = "text-#{font_size} font-semibold text-center py-0.5 px-1 rounded"
      case object.lodging_id
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
      when 4
        if object.confirmed?
          h.content_tag(:span, "Espace Tentes", class: "#{shared_classes} bg-emerald-400 text-emerald-800")
        else
          h.content_tag(:span, "Espace Tentes", class: "#{shared_classes} border border-emerald-200 text-emerald-800")
        end
      end
    end
  end

  def name
    if object.from_airbnb?
      h.raw("#{object.firstname} #{object.lastname}" + h.render("shared/airbnb_icon"))
    elsif object.from_bookingdotcom?
      h.raw("#{object.firstname} #{object.lastname}" + h.render("shared/bookingdotcom_icon"))
    elsif object.from_web?
      h.raw("#{object.firstname} #{object.lastname}" + h.render("shared/web_icon"))
    else
      "#{object.firstname} #{object.lastname}"
    end
  end

  def options_emojis
    emojis = []
    if object.option_partyhall?
      emojis << "🥳"
    end
    if object.option_pizza_party?
      emojis << "🍕"
    end
    if object.option_bread?
      emojis << "🍞"
    end
    if object.option_babysitting?
      emojis << "🍼"
    end
    if object.option_discgolf?
      emojis << "🥏"
    end
    emojis.join(" ")
  end

  def options_text
    text = []
    text << "location de la salle" if object.option_partyhall?
    text << "Pizza Party privée" if object.option_pizza_party?
    text << "pains et viennoiseries" if object.option_bread?
    text << "baby-sitting" if object.option_babysitting?
    text << "initiation au disc-golf" if object.option_discgolf?
    text.join(", ")
  end

  def payment_background
    case object.payment_status
    when "pending"
      "bg-red-100"
    when "partially_paid"
      "bg-yellow-100"
    when "paid"
      "bg-green-100"
    else
      "bg-white"
    end
  end

  def payment_method
    case object.payment_method
    when "cash"
      "En liquide à votre arrivée"
    when "bank_transfer"
      "Virement bancaire"
    when "airbnb"
      "Via Airbnb"
    when "bookingdotcom"
      "Via Booking.com"
    end
  end

  def payment_badge
    case object.payment_method
    when "cash"
      label = "Liquide"
    when "bank_transfer"
      label = "Virement"
    when "airbnb"
      label = "Airbnb"
    when "bookingdotcom"
      label = "Booking.com"
    end
    shared_classes = "text-sm font-medium mr-2 px-2.5 py-0.5 rounded"
    case object.payment_status
    when "pending"
      h.content_tag(:span, label, class: "#{shared_classes} bg-red-200 text-red-800")
    when "partially_paid"
      h.content_tag(:span, label, class: "#{shared_classes} bg-yellow-200 text-yellow-800")
    when "paid"
      h.content_tag(:span, label, class: "#{shared_classes} bg-green-200 text-green-800")
    end
  end

  def payment_status
    shared_classes = "booking-#{object.id}-payment-status text-xs font-medium mr-2 px-2.5 py-0.5 rounded"
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

  def people_emojis
    emojis = []
    if object.adults > 0
      emojis << "#{object.adults} 🧑"
    end
    if object.children > 0
      emojis << "#{object.children} 👨‍👧"
    end
    if object.babies > 0
      emojis << "#{object.babies} 🧑‍🍼"
    end
    emojis.join(" ")
  end

  def phone
    object.phone.present? ? object.phone : "-"
  end

  def price
    if object.undefined_price?
      "à définir"
    else
      h.humanized_money_with_symbol(object.price) 
    end
  end

  def payments_total
    h.content_tag :span,
                  h.number_to_currency(payments.sum(:amount_cents) / 100.0),
                  id: "booking-#{object.id}-payments-sum"
  end

  def public__name
    "#{object.firstname} #{object.lastname}"
  end

  def rooms_badges(font_size: "xs")
    rooms = Room.where(id: object.reservations.map(&:room_id).uniq)
    shared_classes = "text-#{font_size} font-semibold text-center py-0.5 px-1 rounded"
    html = ""
    rooms.each do |room|
      case room.level
      when -1
        if object.confirmed?
          specific_classes = "bg-slate-100 text-slate-800"
        else
          specific_classes = "border border-slate-100 text-slate-800"
        end
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

  def to_date(format: :short)
    l(object.to_date, format: format)
  end

  def token
    h.link_to(
      object.token,
      h.public_booking_path(object.token),
      target: "_blank",
      class: "text-blue-500 border-b-2 border-blue-200 hover:text-blue-700 focus:text-blue-700"
    )
  end

  def towels
    object.towels? ? "OUI" : "non"
  end

  def tr_border_class
    classes = ["border-l-8"]
    if object.lodging.nil?
      classes << ["border-teal-500"]
    else
      classes << ["border-orange-500"]
    end
    classes.join(" ")
  end

  def tr_class
    if object.deleted?
      "bg-stone-50 opacity-50"
    elsif object.confirmed?
      "bg-white"
    elsif object.declined?
      "bg-red-50 opacity-75"
    else
      "bg-yellow-50 opacity-75"
    end
  end

  def wifi_emoji
    object.wifi? ? h.content_tag(:span, h.raw("👩‍💻 <a href='https://les4sources.notion.site/Appareils-WiFi-febf850431bc42b68e455574cc32e951?pvs=4' target='_blank' class='claudy-link'>Installer le WiFi</a>"), class: "text-sm") : nil 
  end
end
