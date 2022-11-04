class BookingDecorator < ApplicationDecorator
  delegate_all

  def from_date
    l(object.from_date, format: :short)
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
end
