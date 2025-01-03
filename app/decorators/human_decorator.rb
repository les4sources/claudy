class HumanDecorator < ApplicationDecorator
  delegate_all

  def status_badge
    case object.status
    when "active"
      h.content_tag(:span, "actif", class: "inline-flex items-center rounded-md bg-green-50 px-1.5 py-0.5 text-xs font-medium text-green-700 ring-1 ring-inset ring-green-600/20")
    when "inactive"
      h.content_tag(:span, "inactif", class: "inline-flex items-center rounded-md bg-red-50 px-1.5 py-0.5 text-xs font-medium text-red-700 ring-1 ring-inset ring-red-600/20")
    end
  end
end
