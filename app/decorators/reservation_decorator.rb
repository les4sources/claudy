class ReservationDecorator < ApplicationDecorator
  delegate_all

  def from_date
    l(object.from_date, format: :short)
  end

  def to_date
    l(object.to_date, format: :short)
  end
end
