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

  def monthly_reports_bar(date)
    out = ActiveSupport::SafeBuffer.new
    out << h.content_tag(:div, class: "inline-flex") do
      bookings_counter = 0
      date.upto(date.end_of_month).each do |current_date|
        if object.booked_on?(current_date)
          bookings_counter += 1
          out << h.content_tag(:div, nil, class: "w-1 h-2 mr-px bg-red-500")
        else
          out << h.content_tag(:div, nil, class: "w-1 h-2 mr-px bg-green-500")
        end
        out << h.content_tag(:div, id: "tooltip-lodging-#{object.id}-#{current_date.iso8601}", role: "tooltip", class: "absolute z-20 invisible inline-block px-3 py-2 text-sm font-medium text-white transition-opacity duration-300 bg-gray-900 rounded-lg shadow-sm opacity-0 tooltip") do
          out << bookings_counter
          out << h.content_tag(:div, class: "tooltip-arrow", data: { "popper-arrow": true })
        end
      end
      out
    end
    out.html_safe
  end
end
