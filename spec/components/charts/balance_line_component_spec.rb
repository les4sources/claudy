require "rails_helper"

# La courbe de trésorerie (2026-09-29) : l'historique en trait plein, la
# projection en marches pointillées, et chaque point survolable.
RSpec.describe Charts::BalanceLineComponent, type: :component do
  Pt = Struct.new(:date, :balance_cents, keyword_init: true) unless defined?(Pt)

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

  it "donne à chaque point sa date et son montant au survol" do
    render_inline(described_class.new(history: history, projection: projection, today: today))

    titles = page.all("circle[data-balance-point] title", visible: :all).map(&:text)
    expect(titles.size).to eq(5)
    expect(titles.last).to include("(projeté)")
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
