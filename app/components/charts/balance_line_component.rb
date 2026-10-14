# La courbe d'un solde dans le temps : l'historique en trait plein, la
# projection en pointillé, un repère « aujourd'hui » entre les deux. Rendu en SVG
# côté serveur, comme `StackedBarsComponent`, et pour la même raison : pas de
# librairie de graphes pour tracer deux lignes.
#
#   = render Charts::BalanceLineComponent.new(history: treasury.history,
#                                             projection: treasury.projection,
#                                             today: treasury.today)
#
# `history` et `projection` sont des collections d'objets répondant à `date` et
# `balance_cents` — typiquement les `Finance::Treasury::Point`. La projection
# se dessine en MARCHES : un solde ne glisse pas d'un encaissement à l'autre, il
# saute le jour où l'argent arrive.
#
# L'axe du temps est COUPÉ EN DEUX à aujourd'hui (Michael, 2026-10-14) : les
# 90 jours projetés prennent `PROJECTION_SHARE` de la largeur au lieu du
# cinquième qu'une échelle linéaire leur laisse face à douze mois d'historique.
# Sinon les marches de la projection, un cercle par jour où l'argent bouge,
# s'empilent les unes sur les autres.
#
# Au survol, `balance-chart` (Stimulus) suit le point le plus proche de la
# souris et dit sa date, son solde et, pour un point projeté, les mouvements
# du jour : quel séjour rentre, quelle facture ou charge fixe sort.
#
# L'axe part TOUJOURS de zéro, ou passe sous zéro si le solde y descend : une
# trésorerie tronquée à 6 000 € fait d'une baisse de 2 000 € un effondrement,
# et c'est la ligne du zéro qu'on regarde en premier.
class Charts::BalanceLineComponent < ViewComponent::Base
  PLOT_WIDTH   = 760
  PLOT_HEIGHT  = 220
  AXIS_WIDTH   = 60
  TOP_MARGIN   = 16
  LABEL_HEIGHT = 24
  RIGHT_MARGIN = 12
  GRID_LINES   = 4
  PROJECTION_SHARE = 0.4
  # Au-delà, la bulle de survol résume : un jour chargé ne doit pas couvrir
  # tout le graphique.
  HOVER_MOVEMENTS = 8

  LINE_COLOR = "#024442".freeze # 4s-main
  NEGATIVE_COLOR = "#b91c1c".freeze

  def initialize(history:, projection:, today:, title: "Évolution de la trésorerie")
    super()
    @history = history.to_a
    @projection = projection.to_a
    @today = today
    @title = title
  end

  attr_reader :title, :today

  def empty? = points.empty?

  def axis_width = AXIS_WIDTH

  def width = AXIS_WIDTH + PLOT_WIDTH + RIGHT_MARGIN

  def height = TOP_MARGIN + PLOT_HEIGHT + LABEL_HEIGHT

  def baseline = TOP_MARGIN + PLOT_HEIGHT

  def line_color = LINE_COLOR

  def negative_color = NEGATIVE_COLOR

  def history_path = polyline(@history.map { |point| xy(point) })

  # Horizontal puis vertical : la marche tombe le jour du mouvement.
  def projection_path
    return nil if @projection.empty?

    coords = []
    @projection.each_with_index do |point, index|
      x, y = xy(point)
      coords << [x, coords.last[1]] if index.positive?
      coords << [x, y]
    end
    polyline(coords)
  end

  def today_x = x_for(@today)

  def zero_y = y_for(0)

  def dips_below_zero? = axis_min_cents.negative?

  # Les graduations, du haut vers le bas.
  def grid_lines
    step = (axis_max_cents - axis_min_cents) / GRID_LINES.to_f
    (0..GRID_LINES).map do |index|
      value = (axis_min_cents + (step * index)).round
      { y: y_for(value), label: short_amount(value) }
    end
  end

  # Le 1er de chaque mois couvert, avec l'initiale du mois — l'année seulement
  # en janvier, pour savoir où l'on change d'année sans charger l'axe.
  def month_ticks
    first = start_date.next_month.beginning_of_month
    first = start_date if start_date.day == 1
    ticks = []
    date = first
    while date <= end_date
      label = I18n.l(date, format: "%b").delete(".")
      label = "#{label} #{date.year}" if date.month == 1
      ticks << { x: x_for(date), label: label }
      date = date.next_month
    end
    ticks
  end

  # Ce que la bulle de survol affiche, un objet par point, de gauche à droite.
  # Le point d'aujourd'hui de l'historique cède la place à celui de la
  # projection, qui porte les mouvements du jour.
  def hover_points
    projected_dates = @projection.map(&:date)
    (@history.reject { |point| projected_dates.include?(point.date) } + @projection).map do |point|
      x, y = xy(point)
      { x: x.round(1), y: y.round(1), projected: projected?(point),
        date: I18n.l(point.date, format: :long).strip, balance: amount(point.balance_cents),
        negative: point.balance_cents.negative?, **movement_lines(point) }
    end
  end

  # Les marches de la projection portent un point visible : chacune est un
  # mouvement attendu, qu'on veut pouvoir survoler.
  def step_markers = hover_points.select { |point| point[:projected] }

  def description
    return "Aucun solde à afficher." if empty?

    now = @history.last || @projection.first
    lowest = @projection.min_by(&:balance_cents)
    parts = ["Solde au #{I18n.l(now.date, format: :long)} : #{amount(now.balance_cents)}."]
    parts << "Point bas projeté : #{amount(lowest.balance_cents)} le #{I18n.l(lowest.date, format: :long)}." if lowest
    parts.join(" ")
  end

  def amount(cents) = number_to_currency(cents / 100.0, unit: "€")

  private

  def points = @history + @projection

  def projected?(point) = @projection.include?(point)

  # Les mouvements du jour, les plus gros d'abord, et combien on n'en montre pas.
  def movement_lines(point)
    moves = point.respond_to?(:movements) ? point.movements.to_a : []
    shown = moves.sort_by { |move| -move.amount_cents.abs }.first(HOVER_MOVEMENTS)
    lines = shown.map do |move|
      { label: move.label, amount: signed_amount(move.amount_cents), incoming: move.amount_cents.positive? }
    end
    { movements: lines, more: moves.size - shown.size }
  end

  def signed_amount(cents) = "#{cents.negative? ? '−' : '+'} #{amount(cents.abs)}"

  def start_date = @start_date ||= points.map(&:date).min

  def end_date = @end_date ||= points.map(&:date).max

  def xy(point) = [x_for(point.date), y_for(point.balance_cents)]

  # Deux échelles linéaires bout à bout : l'historique jusqu'à aujourd'hui,
  # puis la projection sur `PROJECTION_SHARE` de la largeur. Sans historique
  # (ou sans projection), l'autre moitié prend toute la place.
  def x_for(date)
    if date <= split_date
      scale(date, start_date, split_date, AXIS_WIDTH, split_x)
    else
      scale(date, split_date, end_date, split_x, AXIS_WIDTH + PLOT_WIDTH)
    end
  end

  def split_date = @today.clamp(start_date, end_date)

  def split_x
    @split_x ||= if split_date == start_date then AXIS_WIDTH.to_f
                 elsif split_date == end_date then (AXIS_WIDTH + PLOT_WIDTH).to_f
                 else AXIS_WIDTH + (PLOT_WIDTH * (1 - PROJECTION_SHARE))
                 end
  end

  def scale(date, from, to, x_from, x_to)
    span = (to - from).to_f
    return x_from.to_f if span.zero?

    x_from + ((x_to - x_from) * (date - from) / span)
  end

  def y_for(cents)
    range = (axis_max_cents - axis_min_cents).to_f
    return baseline.to_f if range.zero?

    baseline - (PLOT_HEIGHT * (cents - axis_min_cents) / range)
  end

  def polyline(coords)
    return nil if coords.empty?

    coords.map { |x, y| "#{x.round(1)},#{y.round(1)}" }.join(" ")
  end

  def axis_max_cents
    @axis_max_cents ||= nice_ceiling([points.map(&:balance_cents).max.to_i, 0].max)
  end

  def axis_min_cents
    @axis_min_cents ||= begin
      lowest = points.map(&:balance_cents).min.to_i
      lowest.negative? ? -nice_ceiling(-lowest) : 0
    end
  end

  # Un plafond « rond » (1, 2, 2,5, 5 ou 10 × une puissance de dix) plutôt que
  # le maximum brut : une graduation à 3 847 € ne se lit pas.
  def nice_ceiling(raw)
    return 0 if raw.zero?

    magnitude = 10**Math.log10(raw).floor
    step = [1, 2, 2.5, 5, 10].find { |factor| magnitude * factor >= raw } || 10
    (magnitude * step).to_i
  end

  # « 12 k€ » plutôt que « 12 000,00 € », qui déborderait sur le graphe.
  def short_amount(cents)
    euros = cents / 100
    sign = euros.negative? ? "−" : ""
    euros = euros.abs
    return "#{sign}#{ActiveSupport::NumberHelper.number_to_delimited(euros)} €" if euros < 1_000

    rounded = ActiveSupport::NumberHelper.number_to_rounded(
      euros / 1_000.0, precision: euros >= 10_000 ? 0 : 1, strip_insignificant_zeros: true
    )
    "#{sign}#{rounded} k€"
  end
end
