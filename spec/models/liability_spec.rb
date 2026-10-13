require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Dettes et litiges sans facture (2026-10-13) : la taxe d'hébergement d'Yvoir,
# réclamée 12 000 €, contestée, qu'on paiera entre 6 000 et 12 000 €.
RSpec.describe Liability do
  include FinanceBuilders

  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let(:today) { Date.new(2026, 10, 13) }

  def taxe(**attrs)
    Liability.new({ legal_entity: entity, label: "Taxe d'hébergement 2021-2025", kind: "dispute",
                    claimed_cents: 1_200_000, low_cents: 600_000, high_cents: 1_200_000,
                    retained_cents: 1_200_000 }.merge(attrs))
  end

  it "lit les montants saisis à la belge" do
    dette = taxe(claimed: "12 000", low: "6.000,00".delete("."), high: "12000", retained: "9 500,50", paid: "")
    expect(dette.claimed_cents).to eq(1_200_000)
    expect(dette.low_cents).to eq(600_000)
    expect(dette.retained_cents).to eq(950_050)
    expect(dette.paid_cents).to eq(0)
  end

  it "retient par prudence le haut de la fourchette, sinon le réclamé" do
    expect(described_class.prudent_retained_cents(claimed_cents: 1_200_000, high_cents: 1_000_000)).to eq(1_000_000)
    expect(described_class.prudent_retained_cents(claimed_cents: 1_200_000, high_cents: nil)).to eq(1_200_000)
  end

  it "refuse une fourchette à l'envers, un retenu hors fourchette, un payé au-delà du retenu" do
    expect(taxe(low_cents: 1_300_000)).not_to be_valid
    expect(taxe(retained_cents: 500_000)).not_to be_valid
    expect(taxe(paid_cents: 1_300_000)).not_to be_valid
    expect(taxe).to be_valid
  end

  it "sort en une fois à la date probable, ou aujourd'hui sans date" do
    expect(taxe(expected_on: Date.new(2026, 12, 15)).schedule(today: today).map(&:to_h))
      .to eq([{ due_on: Date.new(2026, 12, 15), amount_cents: 1_200_000 }])
    expect(taxe.schedule(today: today).map(&:due_on)).to eq([today])
  end

  it "étale en mensualités, éteint d'abord les premières avec ce qui est payé, et ramène l'échu à aujourd'hui" do
    dette = taxe(expected_on: Date.new(2026, 9, 1), installments: 4, paid_cents: 400_000)
    expect(dette.schedule(today: today).map { |i| [i.due_on, i.amount_cents] }).to eq([
      [today, 200_000],                    # octobre : 300 000 dont 100 000 déjà couverts, et échu
      [Date.new(2026, 11, 1), 300_000],
      [Date.new(2026, 12, 1), 300_000]
    ])
    expect(dette.remaining_cents).to eq(800_000)
    expect(dette.last_due_on).to eq(Date.new(2026, 12, 1))
  end

  it "ne pèse plus une fois soldée ou abandonnée, et date sa clôture" do
    dette = taxe
    dette.update!(status: "dropped")
    expect(dette.closed_on).to eq(Date.current)
    expect(dette.remaining_cents).to eq(0)
    expect(dette.schedule(today: today)).to be_empty
    dette.update!(status: "open")
    expect(dette.closed_on).to be_nil
  end
end
