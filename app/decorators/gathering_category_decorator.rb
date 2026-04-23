class GatheringCategoryDecorator < ApplicationDecorator
  delegate_all

  def color_dot(size: "h-3 w-3")
    h.content_tag(:span, "", class: "inline-block #{size} rounded-full bg-#{object.color}-400")
  end

  def default_start_time_label
    return "variable" if object.default_start_time.blank?
    object.default_start_time.strftime("%H:%M")
  end

  def default_duration_label
    return "variable" if object.default_duration_minutes.blank?
    minutes = object.default_duration_minutes
    hours, rem = minutes.divmod(60)
    if hours.zero?
      "#{rem} min"
    elsif rem.zero?
      "#{hours}h"
    else
      "#{hours}h#{format('%02d', rem)}"
    end
  end
end
