class EventDecorator < ApplicationDecorator
  delegate_all
  decorates_association :event_category

  def calendar_class
    classes = ["shadow", "border-l-4", "border-l-blue-500", "bg-blue-50"]
    # if !object.confirmed?
    #   classes << ["opacity-50"] 
    # end
    classes.join(" ")
  end

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

  def sales_amount
    h.number_to_currency(object.sales_amount)
  end

  def url
    if object.url.presence
      h.link_to("Informations", object.url, target: "_blank", class: "claudy-link")
    end
  end
end
