# Formatage d'affichage d'un article du catalogue (issue #157).
class CatalogItemDecorator < ApplicationDecorator
  delegate_all

  def member_price(on: Date.current)
    format_cents(price_on(on)&.member_price_cents)
  end

  def public_price(on: Date.current)
    format_cents(price_on(on)&.public_price_cents)
  end

  def purchase_price(on: Date.current)
    format_cents(price_on(on)&.purchase_price_cents)
  end

  def reference_price(on: Date.current)
    format_cents(price_on(on)&.reference_price_cents)
  end

  # « depuis le 1 septembre 2026 », ou l'absence de palier dite franchement.
  def price_period(on: Date.current)
    price = price_on(on)
    return "aucun palier" if price.nil?

    from = h.l(price.active_from, format: :long).squish
    price.open_ended? ? "depuis le #{from}" : "du #{from} au #{h.l(price.active_until, format: :long).squish}"
  end

  def channel_badge_css
    case object.channel
    when "bar" then "bg-amber-100 text-amber-800"
    when "grocery" then "bg-emerald-100 text-emerald-800"
    else "bg-gray-100 text-gray-700"
    end
  end

  def unit_suffix = "/ #{object.unit_label}"

  private

  def format_cents(cents)
    cents.nil? ? "—" : h.number_to_currency(cents / 100.0)
  end
end
