class BookingDecorator < ApplicationDecorator
  delegate_all

  def children
    (object.children || 0) > 0 ? object.children : "aucun"
  end

  def bedsheets
    object.bedsheets? ? "OUI" : "non"
  end

  def email
    object.email.present? ? mail_to(object.email) : "-"
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
    "#{object.firstname} #{object.lastname}"
  end

  def payment_method
    case object.payment_method
    when "cash"
      "En liquide"
    when "bank_transfer"
      "Virement bancaire"
    end
  end

  def payment_status
    case object.payment_status
    when "unpaid"
      h.content_tag(:span, "Non payée", class: "alert label")
    when "partially_paid"
      h.content_tag(:span, "Payée partiellement", class: "warning label")
    when "paid"
      h.content_tag(:span, "Payée", class: "success label")
    end
  end

  def phone
    object.phone.present? ? object.phone : "-"
  end

  def status
    case object.status
    when "canceled"
      h.content_tag(:span, "Annulée", class: "alert label")
    when "confirmed"
      h.content_tag(:span, "Confirmée", class: "success label")
    when "pending"
      h.content_tag(:span, "En attente", class: "warning label")
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
