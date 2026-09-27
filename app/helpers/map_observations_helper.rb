# Les relevés de biodiversité (epic #348, phase 13) : la feuille de la flore et
# la patte de la faune. MÊMES tracés que `OBSERVATION_GLYPHS` dans
# `app/frontend/utils/map_biodiversity.js`, qui dessine les marqueurs : les
# changer des deux côtés à la fois.
module MapObservationsHelper
  OBSERVATION_GLYPHS = {
    "flora" => '<path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10Z"/>' \
               '<path d="M2 21c0-3 1.85-5.36 5.08-6C9.5 14.52 12 13 13 12"/>',
    "fauna" => '<circle cx="11" cy="4" r="2"/><circle cx="18" cy="8" r="2"/><circle cx="20" cy="16" r="2"/>' \
               '<path d="M9 10a5 5 0 0 1 5 5v3.5a3.5 3.5 0 0 1-6.84 1.045Q6.52 17.48 4.46 16.84A3.5 3.5 0 0 1 5.5 10Z"/>'
  }.freeze

  # Vert forêt pour la flore, brun écorce pour la faune.
  OBSERVATION_COLORS = { "flora" => "#2E7D4F", "fauna" => "#8A6F47" }.freeze

  def observation_glyph(realm, css_class: "h-4 w-4")
    glyph = OBSERVATION_GLYPHS.fetch(realm.to_s, OBSERVATION_GLYPHS["flora"])
    tag.svg(glyph.html_safe, xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: "none", # rubocop:disable Rails/OutputSafety
                             stroke: "currentColor", "stroke-width": 2, "stroke-linecap": "round",
                             "stroke-linejoin": "round", class: css_class, "aria-hidden": true)
  end

  def observation_color(realm) = OBSERVATION_COLORS.fetch(realm.to_s, OBSERVATION_COLORS["flora"])

  def species_count_label(count)
    count == 1 ? "1 espèce distincte" : "#{count} espèces distinctes"
  end
end
