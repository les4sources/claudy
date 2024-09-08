class StayItemDateDecorator < ApplicationDecorator
  delegate_all

  decorates_association :stay

  def booking_date
    l(object.booking_date, format: :short)
  end
end
