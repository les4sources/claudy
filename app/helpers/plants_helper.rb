# La fiche plante (epic #348, phase 7) : pictogrammes de strate et couleurs de
# santé, les mêmes que les marqueurs de la carte (`utils/map_plants.js` — garder
# les deux en phase).
module PlantsHelper
  # Tracés 24 × 24, trait `currentColor`.
  STRATUM_GLYPHS = {
    "tree" => '<circle cx="12" cy="9" r="6"/><path d="M12 15v7"/>',
    "coppice" => '<circle cx="8" cy="9" r="4"/><circle cx="16" cy="9" r="4"/><path d="M8 13l4 9 4-9"/>',
    "pollard" => '<path d="M10 22V12h4v10"/><path d="M10 12 6 4M12 12V3M14 12l4-8"/>',
    "food_pollard" => '<path d="M10 22V12h4v10"/><path d="M10 12 6 4M12 12V3M14 12l4-8"/>',
    "espalier" => '<path d="M12 22V4M12 9H5M12 9h7M12 15H6M12 15h6"/>',
    "shrub" => '<path d="M4 18a4 4 0 0 1 3-6 5 5 0 0 1 10 0 4 4 0 0 1 3 6z"/><path d="M12 18v4"/>',
    "subshrub" => '<path d="M6 19a3 3 0 0 1 3-5 3 3 0 0 1 6 0 3 3 0 0 1 3 5z"/><path d="M12 19v3"/>',
    "herbaceous" => '<path d="M12 22V10"/><path d="M12 14c-4 0-6-3-6-7 4 0 6 3 6 7zM12 12c0-4 2-7 6-7 0 4-2 7-6 7z"/>',
    "climber" => '<path d="M12 22V3"/><path d="M12 7c3 0 4 2 4 4s-2 3-4 3M12 14c-3 0-4 2-4 3.5"/>',
    "vine" => '<path d="M12 22V3"/><path d="M12 7c3 0 4 2 4 4s-2 3-4 3M12 14c-3 0-4 2-4 3.5"/>',
    "groundcover" => '<path d="M2 17c3-4 5-4 7 0 2-4 4-4 6 0 2-4 4-4 7 0"/><path d="M2 21h20"/>',
    "aquatic" => '<path d="M12 3c-3 4-6 7-6 11a6 6 0 0 0 12 0c0-4-3-7-6-11z"/>'
  }.freeze
  DEFAULT_GLYPH = '<circle cx="12" cy="12" r="4"/>'.freeze

  # Pastille de santé : fond, texte, et la couleur exacte du marqueur.
  HEALTH_STYLES = {
    "healthy" => { pill: "bg-forest-tint text-forest ring-forest/20", dot: "#1F5F4A" },
    "worrying" => { pill: "bg-amber-50 text-amber-800 ring-amber-200", dot: "#E0A351" },
    "sick" => { pill: "bg-red-50 text-red-700 ring-red-200", dot: "#C2553F" }
  }.freeze
  UNKNOWN_HEALTH = { pill: "bg-stone-100 text-stone-600 ring-stone-200", dot: "#7C8F86" }.freeze
  DEAD_COLOR = "#A8A29E".freeze

  def plant_stratum_glyph(stratum, css: "h-5 w-5")
    paths = STRATUM_GLYPHS.fetch(stratum.to_s, DEFAULT_GLYPH)
    tag.svg(paths.html_safe, class: css, xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: "none",
                             stroke: "currentColor", "stroke-width": 1.75, "stroke-linecap": "round",
                             "stroke-linejoin": "round", "aria-hidden": true)
  end

  def plant_health_style(plant)
    plant.dead? ? { pill: "bg-stone-200 text-stone-600 ring-stone-300", dot: DEAD_COLOR } : HEALTH_STYLES.fetch(plant.health, UNKNOWN_HEALTH)
  end

  # « 24,50 € » pour le champ du formulaire (sans symbole) et la ligne résumé.
  def plant_price_in_euros(plant)
    return if plant.purchase_price_cents.nil?

    number_with_precision(plant.purchase_price_cents / 100.0, precision: 2, separator: ",", delimiter: "")
  end

  # La ligne sous le titre d'une section repliée : ce qu'elle contient déjà.
  def plant_section_summary(*values)
    values.compact_blank.join(" · ").presence
  end
end
