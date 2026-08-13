require "rails_helper"

# Issue #156 — éditer un tarif ouvre une version datée. Le miroir
# `rates.amount_cents` ne bouge que si la nouvelle version couvre aujourd'hui.
RSpec.describe Rates::UpdateAmount do
  let(:rate) { Rate.create!(key: "dome.monthly_flat", amount_cents: 5_000, label: "Dôme") }

  before do
    rate.rate_versions.create!(amount_cents: 5_000, active_from: Date.new(2023, 1, 1))
    Pricing::Rates.reset!
  end

  describe "édition à la date du jour" do
    it "ouvre une version aujourd'hui, clôt la précédente la veille et met à jour le miroir" do
      service = described_class.new(rate: rate)

      expect(service.run(amount_cents: 6_000)).to be(true)

      expect(rate.reload.amount_cents).to eq(6_000)
      expect(service.version.active_from).to eq(Date.current)
      expect(service.version.active_until).to be_nil
      expect(rate.rate_versions.chronological.first.active_until).to eq(Date.current - 1)
    end

    it "rend la nouvelle valeur immédiatement lisible sans date" do
      described_class.new(rate: rate).run(amount_cents: 6_000)

      expect(Pricing::Rates.cents("dome.monthly_flat")).to eq(6_000)
      expect(Pricing::Rates.cents("dome.monthly_flat", on: Date.current)).to eq(6_000)
      expect(Pricing::Rates.cents("dome.monthly_flat", on: Date.new(2023, 6, 1))).to eq(5_000)
    end
  end

  describe "édition à une date future" do
    let(:future) { Date.current + 30 }

    it "ne touche pas à la valeur courante" do
      described_class.new(rate: rate).run(amount_cents: 7_000, active_from: future)

      expect(rate.reload.amount_cents).to eq(5_000)
      expect(Pricing::Rates.cents("dome.monthly_flat")).to eq(5_000)
    end

    it "laisse deux versions cohérentes, jointives et non chevauchantes" do
      described_class.new(rate: rate).run(amount_cents: 7_000, active_from: future)

      versions = rate.rate_versions.chronological.to_a
      expect(versions.size).to eq(2)
      expect(versions.first.active_until).to eq(future - 1)
      expect(versions.last.active_from).to eq(future)
      expect(versions.last.active_until).to be_nil
      expect(Pricing::Rates.cents("dome.monthly_flat", on: future)).to eq(7_000)
    end
  end

  describe "deuxième édition le même jour" do
    it "édite la version existante au lieu d'en empiler une deuxième" do
      described_class.new(rate: rate).run(amount_cents: 6_000)

      expect { described_class.new(rate: rate).run(amount_cents: 6_500) }
        .not_to change { rate.rate_versions.count }

      expect(rate.reload.amount_cents).to eq(6_500)
      expect(rate.rate_versions.most_recent_first.first.amount_cents).to eq(6_500)
    end
  end

  describe "édition rétroactive" do
    it "s'insère entre deux versions sans en écraser aucune" do
      described_class.new(rate: rate).run(amount_cents: 7_000, active_from: Date.current + 30)

      described_class.new(rate: rate).run(amount_cents: 5_500, active_from: Date.new(2024, 1, 1))

      periods = rate.rate_versions.chronological.map { |v| [v.active_from, v.active_until, v.amount_cents] }
      expect(periods).to eq([
        [Date.new(2023, 1, 1), Date.new(2023, 12, 31), 5_000],
        [Date.new(2024, 1, 1), Date.current + 29, 5_500],
        [Date.current + 30, nil, 7_000]
      ])
      # La version rétroactive couvre aujourd'hui : le miroir suit.
      expect(rate.reload.amount_cents).to eq(5_500)
    end
  end

  describe "tarif sans aucune version" do
    let(:orphan) { Rate.create!(key: "pet.balthazar_monthly", amount_cents: 3_000) }

    it "crée sa première version et met à jour le miroir" do
      described_class.new(rate: orphan).run(amount_cents: 3_500)

      expect(orphan.reload.amount_cents).to eq(3_500)
      expect(orphan.rate_versions.count).to eq(1)
    end
  end

  describe "montant invalide" do
    it "échoue sans rien modifier" do
      service = described_class.new(rate: rate)
      service.report_errors = false

      expect(service.run(amount_cents: -1)).to be(false)
      expect(rate.reload.amount_cents).to eq(5_000)
      expect(rate.rate_versions.count).to eq(1)
      expect(rate.rate_versions.first.active_until).to be_nil
    end
  end
end
