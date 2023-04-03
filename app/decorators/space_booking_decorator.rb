class SpaceBookingDecorator < ApplicationDecorator
  delegate_all

  decorates_association :event
  decorates_association :space_reservations

  def self.collection_decorator_class
    PaginatingDecorator
  end

  def calendar_class
    classes = ["shadow", "border-l-4", "border-l-pink-500", "bg-pink-50"]
    if !object.confirmed?
      classes << ["opacity-50"] 
    end
    classes.join(" ")
  end

  def duration
    case object&.space_reservations&.first&.duration
    when "2h"
      "2 heures"
    when "evening"
      "soirée"
    when "day"
      "journée"
    when "fullday"
      "journée + soirée"
    else
      "période non précisée"
    end
  end

  def event_name_with_color
    if object.event.presence
      h.link_to(
        object.event.decorate.name_with_color, 
        h.event_path(object.event),
        class: "text-blue-500 border-b-2 border-blue-200 hover:text-blue-700 focus:text-blue-700"
      )
    else
      ""
    end
  end

  def tr_border_class
    classes = ["border-l-8", "border-green-500"]
    classes.join(" ")
  end

  def date_range
    if from_date == to_date
      "le #{from_date}"
    else
      "du #{from_date} au #{to_date}"
    end
  end

  def deposit_amount
    h.humanized_money_with_symbol(object.deposit_amount)
  end

  def email
    object.email.present? ? h.mail_to(object.email) : "-"
  end

  def from_date
    l(object.from_date, format: :short)
  end

  def group_or_name
    if object.group_name.presence
      group_name
    else
      name
    end
  end

  def name
    "#{object.firstname} #{object.lastname}"
  end

  def paid_amount
    h.humanized_money_with_symbol(object.paid_amount)
  end

  def payment_background
    case object.payment_status
    when "pending"
      "bg-red-100"
    when "partially_paid"
      "bg-yellow-100"
    when "paid"
      "bg-green-100"
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
    else
      label = "?"
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

  def payment_method
    case object.payment_method
    when "cash"
      "En liquide à votre arrivée"
    when "bank_transfer"
      "Virement bancaire"
    end
  end

  def payment_status
    shared_classes = "text-sm font-medium mr-2 px-2.5 py-0.5 rounded"
    case object.payment_status
    when "pending"
      h.content_tag(:span, "Non payée", class: "#{shared_classes} bg-red-200 text-red-800")
    when "partially_paid"
      h.content_tag(:span, "Payée partiellement", class: "#{shared_classes} bg-yellow-200 text-yellow-800")
    when "paid"
      h.content_tag(:span, "Payée", class: "#{shared_classes} bg-green-200 text-green-800")
    else
      h.content_tag(:span, object.payment_status, class: "#{shared_classes} bg-gray-100 text-gray-800")
    end
  end

  def phone
    object.phone.present? ? object.phone : "-"
  end

  def price
    h.humanized_money_with_symbol(object.price)
  end

  def public__name
    "#{object.firstname} #{object.lastname}"
  end

  def spaces_badges(font_size: "xs")
    spaces = Space.where(id: object.space_reservations.map(&:space_id).uniq)
    shared_classes = "text-#{font_size} font-semibold text-center py-0.5 px-1 rounded"
    html = ""
    spaces.each do |space|
      html << h.content_tag(
        :span, 
        space.code, 
        class: "#{shared_classes} bg-indigo-100 text-indigo-800",
        "data-tooltip-target": "tooltip-space-#{space.id}"
      )
    end
    h.raw(html)
  end

  def status
    shared_classes = "text-sm font-medium mr-2 px-2.5 py-0.5 rounded"
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

  def status_emoji
    case object.status
    when "canceled"
      "❌"
    when "confirmed"
      "✅"
    when "pending"
      "⏳"
    when "declined"
      "🙅‍♀️"
    else
      object.status
    end
  end

  def to_date
    l(object.to_date, format: :short)
  end

  def token
    h.link_to(
      "##{object.token}",
      h.public_space_booking_path(object.token),
      target: "_blank",
      class: "text-blue-500 border-b-2 border-blue-200 hover:text-blue-700 focus:text-blue-700"
    )
  end

  def tr_class
    if object.confirmed?
      "bg-white"
    elsif object.declined?
      "bg-red-50 opacity-75"
    else
      "bg-yellow-50 opacity-75"
    end
  end
end
