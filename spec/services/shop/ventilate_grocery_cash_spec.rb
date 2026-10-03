require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #359, décision 15 — la « Caisse épicerie » vidée dans la caisse du
# domaine se répartit entre les trois carnets au prorata des espèces déclarées.
# Claudy propose ; rien ne bouge tant qu'un humain n'a pas validé.
RSpec.describe Shop::VentilateGroceryCash do
  include FinanceBuilders

  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:caisse) { build_cash_account(entity, build_general_account(code: "570000", name: "Caisse"), name: "Caisse du domaine", kind: "cash") }
  let(:bank) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let!(:cellier) { build_general_account(code: "701002", name: "Cellier", klass: 7, nature: "revenue") }
  let!(:boulangerie) { build_general_account(code: "701003", name: "Boulangerie", klass: 7, nature: "revenue") }
  let!(:artisanat) { build_general_account(code: "701005", name: "Artisanat (dépôt-vente)", klass: 7, nature: "revenue") }
  let(:pole) { Team.create!(name: "Pôle Épicerie") }
  let!(:motif) do
    CashMotif.create!(label: "Épicerie", direction: "in", general_account: cellier, legal_entity: entity, team: pole, position: 1)
  end
  let(:june) { Date.new(2026, 6, 1) }
  let(:emilie) { Consignor.create!(name: "Émilie", settlement_mode: "invoice", commission_percent: 20) }

  def cash_line(cents, date = Date.new(2026, 6, 20), label: "Caisse épicerie")
    Finance::RecordCashLine.new(cash_account: caisse, motif: motif, entry_date: date, label: label, amount_cents: cents).run!
  end

  def validated_check(channel, cash_cents)
    ShopMonthlyCheck.create!(channel: channel, period_month: june, cash_total_cents: cash_cents, sheets_total_cents: cash_cents,
                             status: "validated", validated_at: Time.current, bank_received_cents: 0, gap_cents: 0)
  end

  def declare_craft_cash(cents)
    report = emilie.consignment_reports.create!(period_month: june, status: "declared")
    report.consignment_report_lines.create!(label: "Savon", quantity: 1, unit_price_cents: cents, payment_method: "cash")
    report.consignment_report_lines.create!(label: "Bougie", quantity: 1, unit_price_cents: 9_999, payment_method: "qr")
  end

  subject(:service) { described_class.new(month: june) }

  describe "les lignes du mois" do
    it "retient le motif « Épicerie » et le libellé « Caisse épicerie » de l'historique, rien d'autre" do
      avec_motif = cash_line(10_000, label: "Vidange du 20")
      historique = build_cash_entry(caisse, amount_cents: 4_000, entry_date: Date.new(2026, 6, 5), label: "Caisse Epicerie")
      build_cash_entry(caisse, amount_cents: 2_000, entry_date: Date.new(2026, 6, 6), label: "Recette du bar")
      build_cash_entry(bank, amount_cents: 3_000, entry_date: Date.new(2026, 6, 6), label: "Caisse épicerie")
      cash_line(1_000, Date.new(2026, 7, 1))

      expect(service.lines).to eq([historique, avec_motif])
    end
  end

  describe "tant que les contrôles ne sont pas validés" do
    it "ne propose rien et dit pourquoi" do
      cash_line(10_000)
      validated_check("grocery", 6_000)

      expect(service).not_to be_ready
      expect(service.blocker).to include("Boulangerie")
      expect(service.proposals).to eq([])
      expect { service.apply! }.to raise_error(described_class::NotReady)
    end
  end

  describe "une fois les deux carnets validés" do
    before do
      validated_check("grocery", 6_000)
      validated_check("bread", 3_000)
      declare_craft_cash(1_000)
    end

    it "compte les espèces déclarées par carnet, artisans compris" do
      expect(service.declared_cash).to eq(grocery: 6_000, bread: 3_000, craft: 1_000)
    end

    it "propose le prorata au centime, sans rien écrire" do
      entry = cash_line(10_001)

      proposal = service.proposals.sole
      expect(proposal.parts.map { |part| [part.notebook, part.account, part.cents] })
        .to eq([[:grocery, cellier, 6_001], [:bread, boulangerie, 3_000], [:craft, artisanat, 1_000]])
      expect(proposal.parts.sum(&:cents)).to eq(10_001)
      expect(proposal).not_to be_applied
      expect(entry.reload.cash_allocations.sole.general_account).to eq(cellier)
    end

    it "à la validation, contre-passe, réaffecte et repasse chaque ligne en gardant entité et pôle" do
      entry = cash_line(5_000)
      first_journal = entry.journal_entry

      expect(service.apply!).to eq(1)

      entry.reload
      expect(entry.status).to eq("allocated")
      expect(entry.cash_allocations.order(:amount_cents).map { |a| [a.general_account, a.amount_cents] })
        .to eq([[artisanat, 500], [boulangerie, 1_500], [cellier, 3_000]])
      expect(entry.cash_allocations.map(&:team).uniq).to eq([pole])
      expect(entry.cash_allocations.map(&:legal_entity).uniq).to eq([entity])
      expect(entry.journal_entry).to be_present
      expect(entry.journal_entry).not_to eq(first_journal)
    end

    it "ne retouche pas une ligne déjà ventilée" do
      cash_line(5_000)
      service.apply!

      expect(described_class.new(month: june).apply!).to eq(0)
      expect(described_class.new(month: june).proposals.sole).to be_applied
    end

    it "refuse un mois arrêté" do
      cash_line(5_000)
      MonthClosing.create!(period_month: june, closed_at: Time.current)

      expect { service.apply! }.to raise_error(described_class::MonthClosed)
    end
  end

  it "ne répartit rien quand aucune espèce n'est déclarée" do
    validated_check("grocery", 0)
    validated_check("bread", 0)

    expect(service.blocker).to include("Aucune espèce")
  end
end
