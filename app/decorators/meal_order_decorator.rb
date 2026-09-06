# Présentation d'une ligne de cuisine (epic #219, phase 3). Tout ce que la page
# Cuisine et la fiche séjour affichent d'une demande passe par ici — libellés,
# badges, formats de prix. Aucune de ces décisions ne vit dans une vue.
class MealOrderDecorator < ApplicationDecorator
  delegate_all
  decorates_association :stay
  decorates_association :responsible_human

  BADGE_BASE = "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium".freeze

  # Le statut CLIENT : où en est la demande côté client, tenu par l'accueil.
  STATUS_STYLES = {
    "inquiry"   => { label: "Info",     classes: "bg-gray-100 text-gray-700" },
    "requested" => { label: "Ferme",    classes: "bg-indigo-100 text-indigo-800" },
    "confirmed" => { label: "Confirmé", classes: "bg-green-100 text-green-800" },
    "cancelled" => { label: "Annulé",   classes: "bg-red-100 text-red-800" }
  }.freeze

  # La validation CUISINE : est-ce que quelqu'un s'en charge, oui ou non.
  VALIDATION_STYLES = {
    "pending"  => { label: "À valider", classes: "bg-amber-100 text-amber-800" },
    "accepted" => { label: "OK",        classes: "bg-green-100 text-green-800" },
    "refused"  => { label: "Refusé",    classes: "bg-red-100 text-red-800" }
  }.freeze

  NOTES_LIMIT = 80

  def date_label
    return "Sans date" if object.date.blank?

    [h.l(object.date, format: :long), object.moment_label].compact_blank.join(" · ")
  end

  def short_date_label
    return "—" if object.date.blank?

    [h.l(object.date, format: "%-d/%m"), object.moment_label].compact_blank.join(" · ")
  end

  def people_label = "#{object.people} pers."

  def price = h.humanized_money_with_symbol(Money.new(object.price_cents.to_i))

  def unit_price = h.humanized_money_with_symbol(Money.new(object.unit_price_effective_cents))

  def cost = object.cost_cents.nil? ? "—" : h.humanized_money_with_symbol(Money.new(object.cost_cents))

  def margin
    value = object.margin_cents
    return "—" if value.nil?

    h.humanized_money_with_symbol(Money.new(value))
  end

  def status_badge = badge(STATUS_STYLES, object.status)

  # Une demande annulée par le client n'attend plus rien de la cuisine : garder
  # « À valider » à côté d'« Annulé » ne fait qu'appeler un geste qui n'a plus
  # lieu d'être. Un refus, lui, EST la réponse de la cuisine : il reste affiché.
  def validation_badge
    return if object.cancelled? && object.pending?

    badge(VALIDATION_STYLES, object.validation)
  end

  def responsible_label = object.responsible_human&.name.presence || "Personne"

  # On lit l'ASSOCIATION, pas la colonne : `Human` porte un `default_scope` sur
  # `status: "active"`, donc un membre désactivé laisse `responsible_human_id`
  # rempli et `responsible_human` à nil. Lire la colonne masquerait le bouton
  # « Je m'en charge » sur une ligne que plus personne ne porte vraiment.
  def responsible_missing? = object.responsible_human.nil?

  # Notes tronquées pour la ligne ; le texte complet vit dans le `title`.
  def notes_short
    return nil if object.notes.blank?

    object.notes.truncate(NOTES_LIMIT)
  end

  # Ce qui explique une ligne sortie du jeu : le motif d'annulation ou de refus.
  def reason
    return object.cancellation_reason.presence if object.cancelled?
    return object.refusal_reason.presence if object.refused?

    nil
  end

  private

  def badge(styles, value)
    style = styles.fetch(value.to_s, { label: value.to_s.presence || "—", classes: "bg-gray-100 text-gray-700" })
    h.content_tag(:span, style[:label], class: "#{BADGE_BASE} #{style[:classes]}")
  end
end
