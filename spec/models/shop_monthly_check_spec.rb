require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #359, phase 5 — le contrôle mensuel d'un carnet : trois totaux saisis,
# la banque en face, l'écart figé à la validation.
RSpec.describe ShopMonthlyCheck do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let(:bank) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let(:caisse) { build_cash_account(entity, build_general_account(code: "570000", name: "Caisse"), name: "Caisse du domaine", kind: "cash") }
  let!(:cellier) { build_general_account(code: "701002", name: "Cellier", klass: 7, nature: "revenue") }
  let!(:boulangerie) { build_general_account(code: "701003", name: "Boulangerie", klass: 7, nature: "revenue") }
  let(:june) { Date.new(2026, 6, 1) }

  def received(cash_account, cents, date, account: cellier)
    build_cash_entry(cash_account, amount_cents: cents, entry_date: date).tap do |entry|
      allocate(entry, account: account, amount_cents: cents, entity: entity)
    end
  end

  describe ".bank_received_cents" do
    it "additionne les affectations bancaires au compte du carnet sur le mois, et seulement elles" do
      received(bank, 1_500, Date.new(2026, 6, 3))
      received(bank, 2_000, Date.new(2026, 6, 30))
      received(bank, 999, Date.new(2026, 7, 1))
      received(bank, 700, Date.new(2026, 6, 10), account: boulangerie)
      received(caisse, 5_000, Date.new(2026, 6, 15)) # la caisse épicerie n'est pas un virement
      received(bank, 400, Date.new(2026, 6, 12)).update!(status: "excluded", excluded_reason: "doublon")

      expect(described_class.bank_received_cents("grocery", june)).to eq(3_500)
      expect(described_class.bank_received_cents("bread", june)).to eq(700)
    end

    it "suit le compte choisi dans les réglages" do
      autre = build_general_account(code: "701009", name: "Autre", klass: 7, nature: "revenue")
      ShopSetting.current.update!(grocery_account: autre)
      received(bank, 1_500, Date.new(2026, 6, 3))
      received(bank, 800, Date.new(2026, 6, 4), account: autre)

      expect(described_class.bank_received_cents("grocery", june)).to eq(800)
    end

    it "vaut zéro sans compte de produit" do
      cellier.destroy!

      expect(described_class.bank_received_cents("grocery", june)).to eq(0)
    end
  end

  describe "validations" do
    it "n'accepte que les carnets Épicerie et Boulangerie" do
      check = described_class.new(channel: "craft", period_month: june)

      expect(check).not_to be_valid
      expect(check.errors[:channel]).to be_present
    end

    it "ramène la période au premier du mois et refuse un second contrôle du même carnet" do
      described_class.create!(channel: "grocery", period_month: Date.new(2026, 6, 17))
      doublon = described_class.new(channel: "grocery", period_month: june)

      expect(described_class.last.period_month).to eq(june)
      expect(doublon).not_to be_valid
      expect(described_class.new(channel: "bread", period_month: june)).to be_valid
    end

    it "refuse les montants négatifs" do
      expect(described_class.new(channel: "grocery", period_month: june, cash_total_cents: -1)).not_to be_valid
    end
  end

  describe "écart" do
    let(:check) do
      described_class.create!(channel: "grocery", period_month: june, sheets_total_cents: 10_000,
                              transfer_total_cents: 6_500, cash_total_cents: 3_000)
    end

    it "en brouillon, suit la banque : feuilles − banque − espèces" do
      received(bank, 6_000, Date.new(2026, 6, 3))

      expect(check.displayed_gap_cents).to eq(1_000)
      expect(check.unmarked_cents).to eq(500)
      expect(check.transfer_gap_cents).to eq(500)

      received(bank, 1_000, Date.new(2026, 6, 20))
      expect(check.displayed_gap_cents).to eq(0)
    end

    it "validé, ne bouge plus quand un virement arrive après coup" do
      received(bank, 6_000, Date.new(2026, 6, 3))
      check.update!(status: "validated", validated_at: Time.current,
                    bank_received_cents: 6_000, gap_cents: 1_000)

      received(bank, 1_000, Date.new(2026, 6, 20))

      expect(check.reload.displayed_bank_received_cents).to eq(6_000)
      expect(check.displayed_gap_cents).to eq(1_000)
    end

    it "validé, refuse qu'on réécrive ses totaux" do
      check.update!(status: "validated", validated_at: Time.current, bank_received_cents: 0, gap_cents: 7_000)

      expect(check.update(sheets_total_cents: 1)).to be(false)
      expect(check.errors[:base].join).to include("ne se modifie plus")
      expect(check.reload.update(notes: "Feuille 14 tachée")).to be(true)
    end
  end
end
