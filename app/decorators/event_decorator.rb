class EventDecorator < ApplicationDecorator
  delegate_all

  def name_with_color
    html = ""
    html << h.content_tag(:div, nil, class: "inline-flex mr-1 w-3 h-3 rounded-full bg-#{object.event_category.color}-300")
    html << object.name
    h.raw(html)
  end
end
