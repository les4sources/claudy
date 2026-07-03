class SpaceDecorator < ApplicationDecorator
  delegate_all

  def name_and_description
    h.content_tag(:div, name, class: "font-medium text-gray-900") +
    h.content_tag(:span, description, class: "text-xs text-gray-700")
  end

  # Badge « multi-groupe » affiché pour les espaces partagés (capacity > 1,
  # ex. Bois, Pâture est/ouest). Un espace exclusif (salle, capacity 1)
  # n'affiche aucun badge.
  def capacity_badge
    return unless object.shared?

    h.content_tag(
      :span,
      "multi-groupe · #{object.capacity} groupes",
      class: "inline-flex items-center rounded-full bg-orange-100 px-2 py-0.5 text-xs font-medium text-orange-800"
    )
  end

  def monthly_reports_bar(date)
    bookings_dates = SpaceReservation
      .includes(:space_booking)
      .where(date: date..date.end_of_month, space: object, space_booking: { status: "confirmed" })
      .pluck(:date).uniq

    out = ActiveSupport::SafeBuffer.new
    date.upto(date.end_of_month).each do |current_date|
      default_class = current_date.on_weekend? ? "bg-green-500" : "bg-green-300"
      out << h.content_tag(:div, nil, class: "w-1 h-2 #{bookings_dates.include?(current_date) ? "bg-red-500" : default_class} mr-px")
    end
    out.html_safe
  end
end
