module CatalogHelper
  MARGIN_CSS = {
    low: "text-red-600",
    medium: "text-amber-600",
    good: "text-green-700"
  }.freeze

  MARGIN_TITLES = {
    low: "Sous l'objectif minimum de #{CatalogPrice::MARGIN_MINIMUM} %",
    medium: "Entre #{CatalogPrice::MARGIN_MINIMUM} et #{CatalogPrice::MARGIN_COMFORT} % — objectif #{CatalogPrice::MARGIN_TARGET} %",
    good: "À partir de #{CatalogPrice::MARGIN_COMFORT} % — objectif #{CatalogPrice::MARGIN_TARGET} %"
  }.freeze

  # La marge sur coût d'un palier, colorée selon l'objectif (rouge sous 25 %,
  # orange jusqu'à 28 %, vert au-delà). « — » quand il manque l'achat ou le
  # prix public : une marge inventée serait pire qu'une marge absente.
  def catalog_margin_tag(price)
    level = price&.margin_level
    return content_tag(:span, "—", class: "text-gray-400") if level.nil?

    content_tag(:span, "#{price.margin_percent} %",
                class: "font-semibold tabular-nums #{MARGIN_CSS.fetch(level)}",
                title: MARGIN_TITLES.fetch(level),
                data: { margin_level: level })
  end
end
