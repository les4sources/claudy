class ReservationDecorator < ApplicationDecorator
  delegate_all

  decorates_association :booking

  def date
    l(object.date, format: :short)
  end
end
