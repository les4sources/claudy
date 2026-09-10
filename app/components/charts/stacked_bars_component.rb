# Un graphe en barres empilées, douze colonnes, rendu en SVG côté serveur
# (issue #276). Aucune librairie de graphes : le déploiement Hatchbox se fait
# via `yarn.lock`, et ajouter Chart.js pour dessiner 48 rectangles coûterait un
# lockfile réécrit contre un dessin que le serveur sait faire seul.
#
#   = render Charts::StackedBarsComponent.new(series: breakdown.lodging_series, year: @year)
#
# `series` est une collection d'objets répondant à `label`, `color`,
# `monthly_cents` (douze entiers, de janvier à décembre) et `total_cents` —
# typiquement les `Reports::AnnualBreakdown::Series`.
class Charts::StackedBarsComponent < ViewComponent::Base
  PLOT_HEIGHT   = 200
  COLUMN_WIDTH  = 54
  COLUMN_GAP    = 10
  AXIS_WIDTH    = 60
  TOP_MARGIN    = 12
  LABEL_HEIGHT  = 24
  RIGHT_MARGIN  = 8
  GRID_LINES    = 4

  MONTH_LABELS = %w[J F M A M J J A S O N D].freeze

  def initialize(series:, year:, title: "Hébergements — répartition sur l'année")
    super()
    @series = series
    @year   = year
    @title  = title
  end

  attr_reader :series, :year, :title

  def total_cents = series.sum(&:total_cents)

  def empty? = total_cents.zero?

  def axis_width = AXIS_WIDTH

  def column_width = COLUMN_WIDTH

  def width  = AXIS_WIDTH + (12 * COLUMN_WIDTH) + (11 * COLUMN_GAP) + RIGHT_MARGIN

  def height = TOP_MARGIN + PLOT_HEIGHT + LABEL_HEIGHT

  def baseline = TOP_MARGIN + PLOT_HEIGHT

  def monthly_totals
    @monthly_totals ||= (0..11).map { |index| series.sum { |serie| serie.monthly_cents[index].to_i } }
  end

  # Un plafond d'axe « rond » (1, 2, 2,5, 5 ou 10 × une puissance de dix) plutôt
  # que le maximum brut : une graduation à 3 847 € ne se lit pas.
  def axis_max_cents
    @axis_max_cents ||= begin
      raw = monthly_totals.max.to_i
      if raw.zero?
        0
      else
        magnitude = 10**Math.log10(raw).floor
        step = [1, 2, 2.5, 5, 10].find { |factor| magnitude * factor >= raw } || 10
        (magnitude * step).to_i
      end
    end
  end

  # Les graduations, du haut vers le bas, avec leur ordonnée et leur libellé.
  def grid_lines
    return [] if axis_max_cents.zero?

    (0..GRID_LINES).map do |index|
      value = axis_max_cents * index / GRID_LINES
      { y: baseline - (PLOT_HEIGHT * index / GRID_LINES.to_f), value: value, label: short_amount(value) }
    end
  end

  # Une colonne par mois, chaque segment déjà positionné : la vue n'a plus qu'à
  # poser des `rect`.
  def columns
    @columns ||= (0..11).map do |index|
      x = AXIS_WIDTH + (index * (COLUMN_WIDTH + COLUMN_GAP))
      cursor = baseline.to_f
      segments = series.filter_map do |serie|
        cents = serie.monthly_cents[index].to_i
        next if cents <= 0

        segment_height = scaled(cents)
        cursor -= segment_height
        { x: x, y: cursor, width: COLUMN_WIDTH, height: segment_height,
          color: serie.color, label: "#{serie.label} — #{amount(cents)}" }
      end

      { x: x, month: index + 1, letter: MONTH_LABELS[index], segments: segments,
        total_cents: monthly_totals[index] }
    end
  end

  # La légende : chaque série, son total et sa part de l'année.
  def legend_rows
    series.map do |serie|
      { label: serie.label, color: serie.color, amount: amount(serie.total_cents),
        share: share_of(serie.total_cents) }
    end
  end

  def description
    return "Aucun revenu d'hébergement enregistré pour #{year}." if empty?

    parts = series.reject { |serie| serie.total_cents.zero? }
                  .map { |serie| "#{serie.label} #{amount(serie.total_cents)}" }
    "Revenus d'hébergement de #{year}, mois par mois, pour un total de " \
      "#{amount(total_cents)} : #{parts.join(', ')}."
  end

  def amount(cents) = number_to_currency(cents / 100.0, unit: "€")

  def share_of(cents)
    return "—" if total_cents.zero?

    number_to_percentage(cents * 100.0 / total_cents, precision: 1)
  end

  private

  def scaled(cents)
    return 0.0 if axis_max_cents.zero?

    cents * PLOT_HEIGHT / axis_max_cents.to_f
  end

  # Les graduations tiennent en quelques caractères : « 12 k€ » plutôt que
  # « 12 000,00 € », qui déborderait sur le graphe.
  def short_amount(cents)
    euros = cents / 100
    return "#{ActiveSupport::NumberHelper.number_to_delimited(euros)} €" if euros < 1_000

    rounded = ActiveSupport::NumberHelper.number_to_rounded(
      euros / 1_000.0, precision: euros >= 10_000 ? 0 : 1, strip_insignificant_zeros: true
    )
    "#{rounded} k€"
  end
end
