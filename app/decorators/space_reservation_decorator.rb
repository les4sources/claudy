class SpaceReservationDecorator < ApplicationDecorator
  delegate_all

  decorates_association :space_booking

  def date
    l(object.date, format: :short)
  end

  def duration
    case object.duration
    when "2h"
      "2 heures"
    when "evening"
      "soirée"
    when "day"
      "journée"
    when "fullday"
      "journée + soirée"
    end
  end
end
