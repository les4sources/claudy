class SpaceDecorator < ApplicationDecorator
  delegate_all

  def monthly_reports_bar(date)
    bookings_dates = SpaceReservation
      .includes(:space_booking)
      .where(date: date..date.end_of_month, space: object, space_booking: { status: "confirmed" })
      .pluck(:date).uniq

    out = ActiveSupport::SafeBuffer.new
    date.upto(date.end_of_month).each do |current_date|
      out << h.content_tag(:div, nil, class: "w-1 h-2 #{bookings_dates.include?(current_date) ? "bg-red-500" : "bg-green-500"} mr-px")
    end
    out.html_safe
  end
end
