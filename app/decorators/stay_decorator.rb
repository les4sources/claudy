class StayDecorator < ApplicationDecorator
  delegate_all

  STATUS_STYLES = {
    "confirmed" => { label: "Confirmé", classes: "bg-green-100 text-green-800" },
    "pending"   => { label: "En attente", classes: "bg-amber-100 text-amber-800" },
    "canceled"  => { label: "Annulé", classes: "bg-red-100 text-red-800" },
    "cancelled" => { label: "Annulé", classes: "bg-red-100 text-red-800" }
  }.freeze

  PLATFORM_STYLES = {
    "airbnb"        => { label: "Airbnb", classes: "bg-rose-50 text-rose-600 ring-1 ring-rose-100" },
    "bookingdotcom" => { label: "Booking.com", classes: "bg-blue-50 text-blue-700 ring-1 ring-blue-100" }
  }.freeze

  # Premier objet réservable du séjour (Booking / SpaceBooking) — porte le contact.
  def primary_bookable
    @primary_bookable ||= object.stay_items.first&.bookable
  end

  # Badge plateforme (Airbnb / Booking.com) si le séjour provient d'une OTA.
  # nil pour les réservations directes / web. Lit `platform` du bookable
  # (uniforme pour Booking et SpaceBooking).
  def platform_badge
    style = PLATFORM_STYLES[primary_bookable&.try(:platform)]
    return if style.nil?
    h.content_tag(:span, style[:label],
                  class: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium #{style[:classes]}",
                  title: "Réservation provenant de #{style[:label]}")
  end

  def status_badge
    style = STATUS_STYLES.fetch(object.status, { label: object.status.presence || "—", classes: "bg-gray-100 text-gray-700" })
    h.content_tag(:span, style[:label],
                  class: "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium #{style[:classes]}")
  end

  # Plage de dates au format français long (ex. « 12 février 2026 »).
  def date_range
    return "—" if arrival_date.blank? && departure_date.blank?
    from = arrival_date.present? ? h.l(arrival_date, format: :long) : "?"
    to = departure_date.present? ? h.l(departure_date, format: :long) : "?"
    "#{from} → #{to}"
  end

  # Nom/prénom + nom de groupe issus du booking sous-jacent.
  def contact_line
    return "—" if primary_bookable.nil?
    person = [primary_bookable.try(:firstname), primary_bookable.try(:lastname)].compact_blank.join(" ")
    group = primary_bookable.try(:group_name).presence
    [person.presence, group].compact.join(" · ").presence || "—"
  end
end
