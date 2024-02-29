class EventCategoryDecorator < ApplicationDecorator
  delegate_all

  def name
    html = ""
    html << h.content_tag(:div, nil, class: "inline-flex mr-1 w-3 h-3 rounded-full bg-#{object.color}-300")
    html << h.content_tag(:div, object.name, class: "inline-flex text-gray-500 font-light")
    h.raw(html)
  end
end
