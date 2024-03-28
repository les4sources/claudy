class PaymentDecorator < ApplicationDecorator
  delegate_all
  decorates_association :booking

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

  def created_at(format: :default)
    h.l(object.created_at.to_date, format: format)
  end

  def payment_method
    case object.payment_method
    when "cash"
      "Liquide"
    when "bank_transfer"
      "Virement"
    when "airbnb"
      "Airbnb"
    end
  end

  def payment_method_emoji
    case object.payment_method
    when "cash"
      h.content_tag(:div, "💶", class: "ml-1")
    when "bank_transfer"
      h.content_tag(:div, "🏦", class: "ml-1")
    when "airbnb"
      h.render("shared/airbnb_icon")
    end
  end
end
