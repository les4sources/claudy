class ExperienceDecorator < ApplicationDecorator
  delegate_all

  # Couleur de repli pour les activités antérieures à la migration (epic #25,
  # Phase 5) qui n'auraient pas été backfillées.
  FALLBACK_COLOR = "#6b7280".freeze

  def color
    object.color.presence || FALLBACK_COLOR
  end

  # Les couleurs sont en base : impossible de passer par des classes Tailwind
  # (le purge JIT ne voit pas les classes construites à l'exécution). On rend
  # donc la couleur en style inline — fond translucide + liseré plein.
  def calendar_chip_style
    "background-color: #{color}1a; border-left: 3px solid #{color}; color: #{color};"
  end

  def legend_dot_style
    "background-color: #{color};"
  end

  def fixed_price
    h.humanized_money_with_symbol(object.fixed_price)
  end

  def participants
    if object.min_participants && object.max_participants
      "De #{object.min_participants} à #{object.max_participants} participants"
    elsif object.min_participants
      "À partir de #{h.pluralize(object.min_participants, "participant", plural: "participants")}"
    else
      "Jusqu'à #{h.pluralize(object.max_participants, "participant", plural: "participants")}"
    end
  end

  def price
    h.humanized_money_with_symbol(object.price)
  end

  # Durée numérique formatée en français (ex. « 2 h », « 2,5 h »), ou nil.
  def duration_hours
    return nil if object.duration_hours.nil?

    formatted = object.duration_hours.to_d.to_s("F").sub(/\.0+\z/, "").tr(".", ",")
    "#{formatted} h"
  end
end
