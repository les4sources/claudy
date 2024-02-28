class LodgingDecorator < ApplicationDecorator
  delegate_all

  def availability_badge(date)
    if object.available_on?(date)
      h.content_tag(:span, class: "inline-flex items-center gap-x-1.5 rounded-full bg-green-100 px-2 py-2 text-xs font-medium text-green-700") do
        h.content_tag(:svg, class: "h-1.5 w-1.5 fill-green-500", viewBox: "0 0 6 6", "aria-hidden": "true") do
          h.content_tag(:circle, nil, { cx: "3", cy: "3", r: "3" })
        end + object.name
      end
    else
      h.content_tag(:span, class: "inline-flex items-center gap-x-1.5 rounded-full bg-red-100 px-2 py-2 text-xs font-medium text-red-700") do
        h.content_tag(:svg, class: "h-1.5 w-1.5 fill-red-500", viewBox: "0 0 6 6", "aria-hidden": "true") do
          h.content_tag(:circle, nil, { cx: "3", cy: "3", r: "3" })
        end + object.name
      end
    end
  end

  def average_booking_duration(start_date, end_date)
    duration = object.average_booking_duration(start_date, end_date)
    if duration.zero?
      "-"
    else
      "#{duration} #{"jour".pluralize(duration)}"
    end
  end

  def average_booking_people(start_date, end_date)
    people_count = object.average_booking_people(start_date, end_date)
    if people_count.zero?
      "-"
    else
      "#{people_count} #{"personne".pluralize(people_count)}"
    end
  end

  def average_booking_revenue(start_date, end_date)
    h.number_to_currency(object.average_booking_revenue(start_date, end_date) / 100.0)
  end

  def average_night_revenue(start_date, end_date)
    h.number_to_currency(object.average_night_revenue(start_date, end_date) / 100.0)
  end

  def monthly_reports_bar(date)
    bookings_dates = Reservation
      .includes(:booking)
      .where(date: date..date.end_of_month, booking: { status: "confirmed", lodging: object })
      .pluck(:date).uniq

    out = ActiveSupport::SafeBuffer.new
    date.upto(date.end_of_month).each do |current_date|
      default_class = current_date.on_weekend? ? "bg-green-500" : "bg-green-300"
      out << h.content_tag(:div, nil, class: "w-1 h-2 mr-px #{bookings_dates.include?(current_date) ? "bg-red-500" : default_class}")
    end
    out.html_safe
  end

  def occupancy_rate(start_date, end_date, opts={})
    h.number_to_percentage(object.occupancy_rate(start_date, end_date, opts), precision: 0)
  end


  def revenues(start_date, end_date)
    h.number_to_currency(object.revenues(start_date, end_date) / 100.0)
  end
end
