class SpaceDecorator < ApplicationDecorator
  delegate_all

  def monthly_reports_bar(date)
    out = ActiveSupport::SafeBuffer.new
    h.content_tag(:div, class: "inline-flex") do
      date.upto(date.end_of_month).each do |current_date|
        out << h.content_tag(:div, nil, class: "w-1 h-2 #{object.booked_on?(current_date) ? "bg-red-500" : "bg-green-500"} mr-px")
      end
      out
    end.html_safe
  end
end
