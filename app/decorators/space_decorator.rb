class SpaceDecorator < ApplicationDecorator
  delegate_all

  def name_and_description
    h.content_tag(:div, name, class: "font-medium text-gray-900") + 
    h.content_tag(:span, description, class: "text-xs text-gray-700")
  end

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
