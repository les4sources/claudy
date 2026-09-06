require "rails_helper"

# Ce que la cuisine a produit sur une plage (epic #219, phase 5).
RSpec.describe Reports::KitchenRevenue do
  let(:customer) { Customer.create!(email: "report@example.com", first_name: "Groupe", last_name: "Report") }
  let!(:steph) { Human.create!(name: "Stéphanie", email: "steph@les4sources.be", status: "active") }
  let!(:michael) { Human.create!(name: "Michael", email: "michael@les4sources.be", status: "active") }

  def stay(arrival: Date.new(2026, 10, 10))
    Stay.create!(customer: customer, source: "manual", status: "pending",
                 arrival_date: arrival, departure_date: arrival + 2)
  end

  def line(target_stay = stay, **attrs)
    order = MealOrder.new({ stay: target_stay, kind: "repas", people: 10,
                            date: Date.new(2026, 10, 11), responsible_human: steph }.merge(attrs))
    order.skip_notifications = true
    order.tap(&:save!)
  end

  subject(:report) { described_class.new(from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 31)) }

  it "retient les lignes de la plage, à leur propre date" do
    inside  = line
    outside = line(stay, date: Date.new(2026, 11, 5))

    expect(report.lines.map(&:id)).to eq([inside.id])
    expect(outside.reload).to be_persisted
  end

  it "retombe sur l'arrivée du séjour quand la ligne n'a pas de date" do
    dated_nowhere = line(stay(arrival: Date.new(2026, 10, 3)), date: nil)

    expect(report.lines.map(&:id)).to include(dated_nowhere.id)
  end

  it "ignore les demandes d'info, les annulées et les refusées" do
    billable = line
    line(stay, status: "inquiry")
    line(stay, status: "cancelled", cancellation_reason: "annulé")
    line(stay, validation: "refused", refusal_reason: "indisponible")

    expect(report.lines.map(&:id)).to eq([billable.id])
  end

  it "totalise par famille et par personne" do
    line(stay, cost_cents: 6_000)
    line(stay, kind: "buffet_vege", people: 5, responsible_human: michael)

    families = report.by_family.to_h
    expect(families["Repas"].price_cents).to eq(15_000)
    expect(families["Repas"].cost_cents).to eq(6_000)
    expect(families["Repas"].margin_cents).to eq(9_000)
    expect(families["Buffet"].price_cents).to eq(6_000)

    people = report.by_responsible.to_h
    expect(people["Stéphanie"].count).to eq(1)
    expect(people["Michael"].count).to eq(1)
  end

  it "compte un coût nul comme zéro, et le signale" do
    line(stay, cost_cents: nil)

    expect(report.totals.cost_cents).to eq(0)
    expect(report.totals.margin_cents).to eq(report.totals.price_cents)
    expect(report.missing_costs_count).to eq(1)
  end

  it "ventile le chiffre d'affaires par mois pour le reporting annuel" do
    line
    line(stay, date: Date.new(2026, 12, 1), people: 4)

    expect(described_class.revenue_by_month(2026)).to include(10 => 15_000, 12 => 6_000)
  end
end
