class EventDecorator < ApplicationDecorator
  delegate_all

  def name_with_color
    html = ""
    html << h.content_tag(:div, nil, class: "inline-flex mr-1 w-3 h-3 rounded-full bg-#{object.event_category.color}-300")
    html << object.name
    h.raw(html)
  end

  def name_with_date
    "#{object.name} (#{date_range})"
  end

  def date_range
    if object.starts_at.to_date == object.ends_at.to_date
      h.l(object.starts_at.to_date)
    else
      "#{h.l(object.starts_at.to_date)} - #{h.l(object.ends_at.to_date)}"
    end
  end
end
