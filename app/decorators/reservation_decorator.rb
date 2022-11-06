class ReservationDecorator < ApplicationDecorator
  delegate_all

  def date
    l(object.date, format: :short)
  end
end
