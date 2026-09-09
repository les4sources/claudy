require "rails_helper"
require Rails.root.join("spec/support/revenue_share_builders")

# Issue #247 — la génération du relevé. La base est LUE (décision 3) : on somme
# les `price_cents` persistés, on ne rejoue aucune grille tarifaire.
RSpec.describe RevenueShares::Generate do
  include RevenueShareBuilders

  let(:lodging) { build_tiny_house }
  let(:agreement) { build_agreement(lodging) }
  let(:period_from) { Date.new(2026, 1, 1) }

  def generate(from: period_from)
    described_class.new(agreement: agreement, period_from: from).run!
  end

  it "retient les réservations du trimestre et calcule la part" do
    build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 30_000)
    build_tiny_booking(lodging, from: Date.new(2026, 2, 20), price_cents: 20_000)

    statement = generate

    expect(statement.revenue_share_statement_lines.count).to eq(2)
    expect(statement.base_cents).to eq(50_000)
    expect(statement.share_cents).to eq(25_000)
    expect(statement.status).to eq("draft")
    expect(statement.period_to).to eq(Date.new(2026, 3, 31))
  end

  it "écarte une réservation annulée, avec sa raison" do
    build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 30_000)
    annulee = build_tiny_booking(lodging, from: Date.new(2026, 2, 1), price_cents: 90_000,
                                          status: "canceled")

    statement = generate

    expect(statement.base_cents).to eq(30_000)
    selection = RevenueShares::Selection.new(agreement: agreement, period_from: period_from,
                                             period_to: Date.new(2026, 3, 31),
                                             except_statement: statement)
    expect(selection.excluded.map { |e| [e.booking.id, e.reason] }).to include([annulee.id, "annulée"])
  end

  it "écarte une réservation dont le séjour est annulé" do
    reservation = build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 30_000)
    customer = Customer.create!(email: "annule@example.com", first_name: "Client", customer_type: "individual")
    stay = Stay.create!(customer: customer, status: "canceled",
                        arrival_date: reservation.from_date, departure_date: reservation.to_date)
    StayItem.create!(stay: stay, bookable: reservation)

    expect { generate }.to raise_error(described_class::NothingToReport)
  end

  it "écarte une réservation qui arrive hors de la période" do
    a_cheval = build_tiny_booking(lodging, from: Date.new(2025, 12, 28), to: Date.new(2026, 1, 3),
                                           price_cents: 40_000)
    build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 30_000)

    statement = generate

    expect(statement.base_cents).to eq(30_000)
    selection = RevenueShares::Selection.new(agreement: agreement, period_from: period_from,
                                             period_to: Date.new(2026, 3, 31),
                                             except_statement: statement)
    expect(selection.excluded.map { |e| [e.booking.id, e.reason] })
      .to include([a_cheval.id, "arrivée hors période"])
  end

  it "ne relève jamais deux fois la même réservation" do
    build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 30_000)
    generate

    expect { generate(from: Date.new(2026, 4, 1)) }.to raise_error(described_class::NothingToReport)
  end

  it "refuse un second relevé sur la même période" do
    build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 30_000)
    generate

    expect { generate }.to raise_error(described_class::AlreadyReported)
  end

  it "porte au relevé suivant la DIFFÉRENCE d'une réservation dont le prix a changé" do
    reservation = build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 30_000)
    premier = generate
    reservation.update!(price_cents: 34_000)

    suivant = described_class.new(agreement: agreement, period_from: Date.new(2026, 4, 1)).run!
    ligne = suivant.revenue_share_statement_lines.sole

    expect(ligne.kind).to eq("adjustment")
    expect(ligne.amount_cents).to eq(4_000)
    expect(ligne.origin_line).to eq(premier.revenue_share_statement_lines.first)
    expect(suivant.share_cents).to eq(2_000)
  end

  it "sait régulariser une seconde fois sans re-relever la nuitée" do
    reservation = build_tiny_booking(lodging, from: Date.new(2026, 1, 10), price_cents: 30_000)
    generate
    reservation.update!(price_cents: 34_000)
    described_class.new(agreement: agreement, period_from: Date.new(2026, 4, 1)).run!
    reservation.update!(price_cents: 31_000)

    troisieme = described_class.new(agreement: agreement, period_from: Date.new(2026, 7, 1)).run!

    expect(troisieme.base_cents).to eq(-3_000)
    expect(troisieme.revenue_share_statement_lines.sole.kind).to eq("adjustment")
  end

  it "refuse de créer un relevé vide" do
    expect { generate }.to raise_error(described_class::NothingToReport)
  end
end
