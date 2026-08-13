# Formatage d'affichage d'une écriture du grand livre (issue #155).
class AccountEntryDecorator < ApplicationDecorator
  delegate_all

  def amount
    h.number_to_currency(object.amount_cents / 100.0)
  end

  # Un montant dû se lit en rouge, un montant en faveur du compte en vert.
  def amount_css
    object.amount_cents.positive? ? "text-red-600" : "text-emerald-700"
  end

  def entry_date
    h.l(object.entry_date, format: :ddmmyyyy)
  end

  def flow
    object.flow.blank? ? "—" : object.flow_label
  end

  def label
    object.label.presence || "—"
  end

  # 3.0 se lit « 3 », 2.5 se lit « 2,5 » — on ne traîne pas les zéros inutiles.
  def quantity
    value = object.quantity
    return "—" if value.blank?

    h.number_with_precision(value, precision: 3, strip_insignificant_zeros: true)
  end

  def unit_price
    return "—" if object.unit_price_cents.blank?

    h.number_to_currency(object.unit_price_cents / 100.0)
  end

  def lock_icon
    return "" unless object.locked?

    h.content_tag(:span, "🔒",
                  title: "Rattachée à un décompte émis — non modifiable",
                  class: "cursor-help")
  end
end
