class PaymentDecorator < ApplicationDecorator
  delegate_all
  decorates_association :booking

  def amount
    h.number_to_currency(object.amount)
  end

  # Stay-first (epic #26, Phase 2) : un paiement peut désormais n'avoir AUCUN
  # booking (séjour sans hébergement). L'admin liste tous les paiements — il doit
  # donc retomber sur le séjour au lieu de planter sur un `booking_path(nil)`.
  def linked_to_booking?
    object.booking_id.present?
  end

  # Un paiement de COWORKING n'a par conception ni booking ni séjour : il est
  # ancré sur un `CoworkingPack` (cf. la validation
  # `anchored_on_stay_or_coworking_pack` du modèle, qui impose l'un OU l'autre).
  def linked_to_coworking?
    object.coworking_pack_id.present?
  end

  def linked_name
    return booking_name if linked_to_booking?
    return object.coworking_pack&.customer&.name.presence || "Coworking" if linked_to_coworking?

    object.stay&.customer&.name.presence || "Séjour"
  end

  # Cible du lien, dans l'ordre : booking, pack de coworking, séjour. nil s'il
  # n'y a rien — la vue rend alors du texte.
  #
  # C'est ici que /payments tombait : le paiement de coworking n'ayant pas de
  # séjour, on appelait `stay_path(nil)` → UrlGenerationError, et UNE ligne
  # faisait tomber TOUTE la page. `linked_name` gérait déjà le nil, pas le chemin.
  def linked_path
    return h.booking_path(object.booking_id) if linked_to_booking?
    return h.coworking_pack_path(object.coworking_pack_id) if linked_to_coworking?

    object.stay ? h.stay_path(object.stay) : nil
  end

  def linked_payment_status
    return booking_payment_status if linked_to_booking?

    StayDecorator.new(object.stay).payment_status_badge if object.stay
  end

  def linked_date_range
    return booking_date_range if linked_to_booking?

    StayDecorator.new(object.stay).date_range if object.stay
  end

  def booking_date_range
    booking.date_range
  rescue
    booking = get_deleted_booking(booking_id)
    booking.date_range
  end

  def booking_name
    booking.group_or_name
  rescue
    booking = get_deleted_booking(booking_id)
    booking.group_or_name
  end

  def booking_payment_status
    booking.payment_status
  rescue
    booking = get_deleted_booking(booking_id)
    booking.payment_status
  end

  def created_at(format: :default)
    h.l(object.created_at.to_date, format: format)
  end

  def line
    line_content = case object.payment_method
      when "airbnb"
        "Payé #{amount} via Airbnb"
      when "bookingdotcom"
        "Payé #{amount} via Booking.com"
      when "bank_transfer"
        "Payé #{amount} par virement bancaire"
      when "cash"
        "Payé #{amount} en liquide"
      when "stripe"
        "Payé #{amount} en ligne"
      end
    h.content_tag(:p, line_content, class: "text-sm text-gray-900")
  end

  def payment_method
    case object.payment_method
    when "airbnb"
      "Airbnb"
    when "bookingdotcom"
      "Booking.com"
    when "bank_transfer"
      "Virement"
    when "cash"
      "Liquide"
    when "stripe"
      "En ligne"
    end
  end

  def payment_method_emoji
    case object.payment_method
    when "cash"
      h.content_tag(:div, "💶", class: "ml-1")
    when "bank_transfer"
      h.content_tag(:div, "🏦", class: "ml-1")
    when "stripe"
      h.content_tag(:div, "💳", class: "ml-1")
    when "airbnb"
      h.render("shared/airbnb_icon")
    when "bookingdotcom"
      h.render("shared/bookingdotcom_icon")
    end
  end

  def status
    shared_classes = "payment-#{object.id}-status text-xs font-medium mr-2 px-2.5 py-0.5 rounded"
    case object.status
    when "pending"
      h.content_tag(:span, "En attente", class: "#{shared_classes} bg-red-200 text-red-800")
    when "paid"
      h.content_tag(:span, "Payé", class: "#{shared_classes} bg-green-200 text-green-800")
    end
  end

  def tr_class
    if object.status == "paid"
      "text-gray-900"
    else
      "text-gray-500"
    end
  end

  def updated_at(format: :default)
    h.l(object.updated_at.to_date, format: format)
  end

  private

  def get_deleted_booking(booking_id)
    Booking.unscoped.find(booking_id)&.decorate
  end
end
