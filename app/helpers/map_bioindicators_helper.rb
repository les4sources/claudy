# Les relevés de plantes bio-indicatrices : le triangle de l'état du sol (vert
# équilibré, jaune en cours de dégradation, rouge dégradé), gris tant que le
# relevé attend son analyse. MÊMES couleurs que `app/frontend/utils/
# map_bioindicators.js`, qui dessine les marqueurs.
module MapBioindicatorsHelper
  PENDING_COLOR = "#78716C".freeze
  TRIANGLE = '<path d="M12 3.5 21.5 20h-19Z"/>'.freeze
  PENDING = '<circle cx="12" cy="12" r="8.5" stroke-dasharray="3 2.5"/><path d="M12 8.5v4M12 15.5h.01"/>'.freeze

  def bioindicator_color(agronomy)
    BioindicatorVocabulary::AGRONOMY_COLORS.fetch(agronomy.to_s, PENDING_COLOR)
  end

  # Le triangle plein de l'état agronomique ; un cercle pointillé « ! » pour un
  # relevé pas encore analysé.
  def bioindicator_glyph(feature_or_agronomy, css_class: "h-4 w-4")
    agronomy = feature_or_agronomy.respond_to?(:analysis_agronomy) ? feature_or_agronomy.analysis_agronomy : feature_or_agronomy
    analyzed = feature_or_agronomy.respond_to?(:analyzed?) ? feature_or_agronomy.analyzed? : agronomy.present?
    color = bioindicator_color(agronomy)
    if analyzed && agronomy
      tag.svg(TRIANGLE.html_safe, xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: color, # rubocop:disable Rails/OutputSafety
                                  stroke: color, "stroke-width": 1.5, "stroke-linejoin": "round", class: css_class,
                                  style: "color: #{color}", "aria-hidden": true)
    else
      tag.svg(PENDING.html_safe, xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: "none", # rubocop:disable Rails/OutputSafety
                                 stroke: color, "stroke-width": 2, "stroke-linecap": "round", class: css_class,
                                 "aria-hidden": true)
    end
  end

  # « ●●○ » : la force d'un indicateur, lisible d'un coup d'œil.
  def bioindicator_strength(strength)
    strength = strength.to_i.clamp(1, 3)
    label = BioindicatorVocabulary::STRENGTHS[strength]
    tag.span(("●" * strength) + ("○" * (3 - strength)), class: "tracking-tighter", title: "Signe #{label}", "aria-label": "signe #{label}")
  end
end
