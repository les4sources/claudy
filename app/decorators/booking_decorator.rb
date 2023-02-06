class BookingDecorator < ApplicationDecorator
  delegate_all

  def self.collection_decorator_class
    PaginatingDecorator
  end

  def children
    (object.children || 0) > 0 ? object.children : "aucun"
  end

  def bedsheets
    object.bedsheets? ? "OUI" : "non"
  end

  def email
    object.email.present? ? h.mail_to(object.email) : "-"
  end

  def from_date
    l(object.from_date, format: :short)
  end

  def label_bedsheets
    return if !object.bedsheets?
    h.content_tag(:span, "draps", class: "secondary label")
  end

  def label_towels
    return if !object.towels?
    h.content_tag(:span, "essuies", class: "secondary label")
  end

  def name
    if object.from_airbnb?
      h.raw("#{object.firstname} #{object.lastname}" + h.render("shared/airbnb_icon"))
    else
      "#{object.firstname} #{object.lastname}"
    end
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

  def payment_method
    case object.payment_method
    when "cash"
      "En liquide"
    when "bank_transfer"
      "Virement bancaire"
    when "airbnb"
      "Via AirBnb"
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

  def to_date
    l(object.to_date, format: :short)
  end

  def towels
    object.towels? ? "OUI" : "non"
  end
end
