class PaymentDecorator < ApplicationDecorator
  delegate_all
  decorates_association :booking
  decorates_association :stay

  def amount
    h.number_to_currency(object.amount)
  end

  

  def booking_date_range
    booking.date_range
  end

  def booking_name
    booking.group_or_name
  end

  def booking_payment_status
    booking.payment_status
  end

  def stay_date_range
    stay.date_range
  end

  def stay_name
    stay.name
  end

  def stay_payment_status
    stay.payment_status
  end

  def created_at(format: :default)
    h.l(object.created_at.to_date, format: format)
  end

  def line
    line_content = case object.payment_method
      when "airbnb"
        "Payé #{amount} via Airbnb"
      when "bank_transfer"
        "Payé #{amount} par virement bancaire"
      when "cash"
        "Payé #{amount} en liquide"
      when "stripe"
        "Payé #{amount} en ligne"
      end
    h.content_tag(:p, line_content, class: "text-sm text-gray-900")
  end

  def payment_method
    case object.payment_method
    when "airbnb"
      "Airbnb"
    when "bank_transfer"
      "Virement"
    when "cash"
      "Liquide"
    when "stripe"
      "En ligne"
    end
  end

  def payment_method_emoji
    case object.payment_method
    when "cash"
      h.content_tag(:div, "💶", class: "ml-1")
    when "bank_transfer"
      h.content_tag(:div, "🏦", class: "ml-1")
    when "stripe"
      h.content_tag(:div, "💳", class: "ml-1")
    when "airbnb"
      h.render("shared/airbnb_icon")
    end
  end

  def status
    shared_classes = "payment-#{object.id}-status text-xs font-medium mr-2 px-2.5 py-0.5 rounded"
    case object.status
    when "pending"
      h.content_tag(:span, "En attente", class: "#{shared_classes} bg-red-200 text-red-800")
    when "partially_paid"
      h.content_tag(:span, "Acompte", class: "#{shared_classes} bg-yellow-200 text-yellow-800")
    when "paid"
      h.content_tag(:span, "Payé", class: "#{shared_classes} bg-green-200 text-green-800")
    end
  end

  def tr_class
    if object.status == "paid"
      "text-gray-900"
    else
      "text-gray-500"
    end
  end

  def updated_at(format: :default)
    h.l(object.updated_at.to_date, format: format)
  end
end
