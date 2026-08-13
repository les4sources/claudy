# Formatage d'affichage d'une version de barème (issue #156) — l'écran Tarifs
# ne fabrique aucune chaîne lui-même.
class RateVersionDecorator < ApplicationDecorator
  delegate_all

  # « depuis le 1 janvier 2023 » ou « du 1 janvier 2023 au 30 avril 2027 ».
  def period
    return "depuis le #{formatted(object.active_from)}" if object.open_ended?

    "du #{formatted(object.active_from)} au #{formatted(object.active_until)}"
  end

  # Montant lisible, en euros ou en points de pourcentage selon l'unité du tarif.
  def amount
    return "#{object.amount_cents} %" if object.rate.percent?

    h.number_to_currency(object.amount_cents / 100.0)
  end

  private

  # `%e` cadre le jour sur deux caractères : « 1 janvier » plutôt que «  1 janvier ».
  def formatted(date) = h.l(date, format: :long).squish
end
