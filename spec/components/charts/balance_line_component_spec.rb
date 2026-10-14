require "rails_helper"

# La courbe de trésorerie (2026-09-29) : l'historique en trait plein, la
# projection en marches pointillées, et chaque point survolable.
RSpec.describe Charts::BalanceLineComponent, type: :component do
  Pt = Struct.new(:date, :balance_cents, keyword_init: true) unless defined?(Pt)
  Mv = Struct.new(:label, :amount_cents, keyword_init: true) unless defined?(Mv)
  MovingPt = Struct.new(:date, :balance_cents, :movements, keyword_init: true) unless defined?(MovingPt)

  let(:today) { Date.new(2026, 9, 29) }
  let(:history) { [Pt.new(date: Date.new(2026, 8, 1), balance_cents: 500_000), Pt.new(date: today, balance_cents: 400_000)] }
  let(:projection) do
    [Pt.new(date: today, balance_cents: 400_000), Pt.new(date: Date.new(2026, 10, 5), balance_cents: 100_000),
     Pt.new(date: Date.new(2026, 12, 28), balance_cents: 100_000)]
  end

  it "trace l'historique en plein et la projection en pointillé" do
    render_inline(described_class.new(history: history, projection: projection, today: today))

    expect(page).to have_css("svg polyline:not([stroke-dasharray])", count: 1)
    expect(page).to have_css("svg polyline[stroke-dasharray]", count: 1)
  end

  it "dessine la projection en marches : le solde saute le jour du mouvement" do
    component = described_class.new(history: history, projection: projection, today: today)
    render_inline(component)

    coords = page.find("svg polyline[stroke-dasharray]", visible: :all)[:points].split.map { |xy| xy.split(",").map(&:to_f) }
    # Trois points, deux marches intercalées : 5 sommets.
    expect(coords.size).to eq(5)
    expect(coords[1][1]).to eq(coords[0][1])
    expect(coords[1][0]).to eq(coords[2][0])
  end

  def hover_points
    JSON.parse(page.find("[data-controller='balance-chart']", visible: :all)["data-balance-chart-points-value"])
  end

  it "donne au survol la date, le solde et les mouvements du jour" do
    moving = [
      Pt.new(date: today, balance_cents: 400_000),
      MovingPt.new(date: Date.new(2026, 10, 5), balance_cents: 100_000,
                   movements: [Mv.new(label: "Loyer (charge fixe)", amount_cents: -350_000),
                               Mv.new(label: "Séjour #12 — Dupont", amount_cents: 50_000)])
    ]
    render_inline(described_class.new(history: history, projection: moving, today: today))

    # Aujourd'hui n'apparaît qu'une fois : le point projeté remplace celui de l'historique.
    expect(hover_points.map { |p| p["date"] }).to eq(["1 août 2026", "29 septembre 2026", "5 octobre 2026"])
    step = hover_points.last
    expect(step).to include("projected" => true, "more" => 0)
    expect(step["balance"]).to include("1 000,00")
    expect(step["movements"].map { |m| [m["label"], m["amount"], m["incoming"]] }).to eq([
      ["Loyer (charge fixe)", "− 3 500,00 €", false],
      ["Séjour #12 — Dupont", "+ 500,00 €", true]
    ])
    expect(page).to have_css("circle[data-balance-point]", count: 2, visible: :all)
  end

  it "donne à la projection 40 % de la largeur, quelle que soit la longueur de l'historique" do
    long_history = [Pt.new(date: Date.new(2025, 9, 1), balance_cents: 500_000), Pt.new(date: today, balance_cents: 400_000)]
    render_inline(described_class.new(history: long_history, projection: projection, today: today))

    xs = hover_points.map { |p| p["x"] }
    plot = described_class::PLOT_WIDTH
    expect(xs.first).to eq(described_class::AXIS_WIDTH)
    expect(xs.last - xs[1]).to be_within(0.1).of(plot * described_class::PROJECTION_SHARE)
  end

  it "trace la ligne du zéro quand le solde passe dessous" do
    negative = projection + [Pt.new(date: Date.new(2026, 12, 29), balance_cents: -20_000)]
    render_inline(described_class.new(history: history, projection: negative, today: today))

    expect(page).to have_css("line[stroke='#{described_class::NEGATIVE_COLOR}']", visible: :all)
  end

  it "dit son vide" do
    render_inline(described_class.new(history: [], projection: [], today: today))

    expect(page).to have_text("Aucun solde à afficher")
  end
end
