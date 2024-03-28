class PaylinkDecorator < ApplicationDecorator
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

  def created_at
    h.l(object.created_at.to_date)
  end
end
