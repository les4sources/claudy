# Le trafic du site jour par jour (statistiques sans cookie, 2026-10-03) :
# pages vues en barre claire, visites en barre foncée par-dessus. SVG rendu
# côté serveur, comme les autres graphes de Charts:: — aucune librairie.
#
#   = render Charts::DailyTrafficComponent.new(days: @report.daily)
#
# `days` : une liste de { day:, visits:, pageviews: }, du plus ancien au plus récent.
class Charts::DailyTrafficComponent < ViewComponent::Base
  WIDTH        = 960
  PLOT_HEIGHT  = 180
  AXIS_WIDTH   = 44
  TOP_MARGIN   = 10
  LABEL_HEIGHT = 22
  GRID_LINES   = 4
  DATE_LABELS  = 6

  VISITS_COLOR    = "#0f766e"
  PAGEVIEWS_COLOR = "#99f6e4"

  def initialize(days:)
    super()
    @days = days
  end

  attr_reader :days

  def empty? = days.sum { |day| day[:pageviews] }.zero?

  def width = WIDTH

  def height = TOP_MARGIN + PLOT_HEIGHT + LABEL_HEIGHT

  def baseline = TOP_MARGIN + PLOT_HEIGHT

  def axis_width = AXIS_WIDTH

  def visits_color = VISITS_COLOR

  def pageviews_color = PAGEVIEWS_COLOR

  def axis_max
    @axis_max ||= begin
      raw = days.map { |day| day[:pageviews] }.max.to_i
      if raw <= GRID_LINES
        GRID_LINES
      else
        magnitude = 10**Math.log10(raw).floor
        step = [1, 2, 2.5, 5, 10].find { |factor| magnitude * factor >= raw } || 10
        (magnitude * step).ceil
      end
    end
  end

  def grid_lines
    (0..GRID_LINES).map do |index|
      value = axis_max * index / GRID_LINES.to_f
      { y: baseline - (PLOT_HEIGHT * index / GRID_LINES.to_f), label: ActiveSupport::NumberHelper.number_to_delimited(value.round) }
    end
  end

  def slot = (WIDTH - AXIS_WIDTH) / days.size.to_f

  def bar_width = [slot * 0.75, 1.0].max

  def bars
    days.each_with_index.map do |day, index|
      x = AXIS_WIDTH + (index * slot) + ((slot - bar_width) / 2)
      { x: x, width: bar_width,
        pageviews_y: baseline - scaled(day[:pageviews]), pageviews_height: scaled(day[:pageviews]),
        visits_y: baseline - scaled(day[:visits]), visits_height: scaled(day[:visits]),
        label: "#{I18n.l(day[:day], format: '%a %-d %b')} — #{day[:visits]} visite(s), #{day[:pageviews]} page(s) vue(s)" }
    end
  end

  # Quelques dates réparties sous l'axe, pas une par jour.
  def date_labels
    step = [(days.size / DATE_LABELS.to_f).ceil, 1].max
    days.each_with_index.select { |_, index| (index % step).zero? }.map do |day, index|
      { x: AXIS_WIDTH + (index * slot) + (slot / 2), label: I18n.l(day[:day], format: "%-d %b") }
    end
  end

  def description
    total_visits = days.sum { |day| day[:visits] }
    total_views = days.sum { |day| day[:pageviews] }
    "Trafic quotidien du #{I18n.l(days.first[:day])} au #{I18n.l(days.last[:day])} : " \
      "#{total_visits} visites et #{total_views} pages vues."
  end

  private

  def scaled(value)
    value * PLOT_HEIGHT / axis_max.to_f
  end
end
