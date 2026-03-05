class CycleActionDecorator < ApplicationDecorator
  delegate_all

  CATEGORY_STYLES = {
    "rituelle" => { bg: "bg-blue-50", text: "text-blue-700", ring: "ring-blue-600/20", label: "Rituelle", icon: "🔄" },
    "ponctuelle" => { bg: "bg-gray-50", text: "text-gray-700", ring: "ring-gray-600/20", label: "Ponctuelle", icon: "🎯" },
    "reportee" => { bg: "bg-amber-50", text: "text-amber-700", ring: "ring-amber-600/20", label: "Reportée", icon: "⏭" },
    "deleguee" => { bg: "bg-purple-50", text: "text-purple-700", ring: "ring-purple-600/20", label: "Déléguée", icon: "👋" },
    "demandee" => { bg: "bg-rose-50", text: "text-rose-700", ring: "ring-rose-600/20", label: "Demandée", icon: "📣" },
    "invitee" => { bg: "bg-emerald-50", text: "text-emerald-700", ring: "ring-emerald-600/20", label: "Invitée", icon: "✨" }
  }.freeze

  def category_badge
    style = CATEGORY_STYLES[object.category] || CATEGORY_STYLES["ponctuelle"]
    h.content_tag(:span, style[:label],
      class: "inline-flex items-center rounded-full #{style[:bg]} px-2 py-0.5 text-xs font-medium #{style[:text]} ring-1 ring-inset #{style[:ring]}")
  end

  def category_label
    style = CATEGORY_STYLES[object.category]
    style ? style[:label] : object.category.humanize
  end

  def category_icon
    style = CATEGORY_STYLES[object.category]
    style ? style[:icon] : "📋"
  end

  def formatted_hours
    return nil unless object.hours.present? && object.hours > 0
    "#{object.hours.to_f}h"
  end
end
