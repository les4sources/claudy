require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Ce que la cuisine a coûté et encaissé sur une période (epic #269, phase 2).
#
# Ces exemples gardent surtout deux refus : un compte hors périmètre n'entre pas
# dans les dépenses, et sans réglage le service ne se rabat pas sur « tous les
# comptes ».
RSpec.describe Kitchen::AccountingReport do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2026) }

  let!(:repas) { build_general_account(code: "600005", name: "Achats cuisine — repas", klass: 6, nature: "expense") }
  let!(:buffets) { build_general_account(code: "600006", name: "Achats cuisine — buffets", klass: 6, nature: "expense") }
  let!(:autre_charge) { build_general_account(code: "612003", name: "Gaz", klass: 6, nature: "expense") }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:compte_repas) { build_general_account(code: "700200", name: "Repas", klass: 7, nature: "revenue") }
  let!(:compte_locations) { build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue") }

  subject(:report) { described_class.new(from: Date.new(2026, 1, 1), to: Date.new(2026, 12, 31)) }

  def configure_accounts(*accounts)
    Setting.set(Kitchen::Config::EXPENSE_ACCOUNTS_KEY, accounts.map(&:id).join(","))
  end

  def spend(account, cents, on: Date.new(2026, 3, 12), label: "Courses")
    post_simple_entry(entity: entity, debit_account: account, credit_account: banque,
                      amount_cents: cents, entry_date: on, journal: "purchases", label: label)
  end

  def cash_in(account, cents, on: Date.new(2026, 3, 20), label: "Encaissement")
    post_simple_entry(entity: entity, debit_account: banque, credit_account: account,
                      amount_cents: cents, entry_date: on, journal: "bank", label: label)
  end

  describe "les dépenses" do
    before { configure_accounts(repas, buffets) }

    it "totalise les mouvements débiteurs des comptes configurés" do
      spend(repas, 12_000)
      spend(buffets, 8_000)

      expect(report.expenses_cents).to eq(20_000)
      expect(report.expense_lines.size).to eq(2)
    end

    it "ignore une écriture hors période" do
      build_fiscal_year(entity, year: 2025)
      spend(repas, 12_000, on: Date.new(2026, 6, 1))
      spend(repas, 99_000, on: Date.new(2025, 12, 31))

      restreint = described_class.new(from: Date.new(2026, 5, 1), to: Date.new(2026, 6, 30))

      expect(restreint.expenses_cents).to eq(12_000)
      expect(report.expenses_cents).to eq(12_000) # l'écriture 2025 reste dehors
    end

    it "ignore un compte de charge qui n'est pas au périmètre de la cuisine" do
      spend(repas, 12_000)
      spend(autre_charge, 50_000)

      expect(report.expenses_cents).to eq(12_000)
      expect(report.expense_lines.map { |line| line.general_account.code }).to eq(["600005"])
    end

    # Une note de crédit fournisseur passe au crédit d'un compte de charge : elle
    # diminue la dépense au lieu de s'y ajouter.
    it "soustrait un mouvement créditeur d'un compte de charge" do
      spend(repas, 12_000)
      post_simple_entry(entity: entity, debit_account: banque, credit_account: repas,
                        amount_cents: 2_000, entry_date: Date.new(2026, 4, 2),
                        journal: "purchases", label: "Note de crédit")

      expect(report.expenses_cents).to eq(10_000)
    end

    it "rend les lignes dans l'ordre du grand livre, avec leur écriture" do
      spend(buffets, 8_000, on: Date.new(2026, 5, 4), label: "Colruyt")
      spend(repas, 12_000, on: Date.new(2026, 2, 3), label: "Marché")

      dates = report.expense_lines.map { |line| line.journal_entry.entry_date }
      expect(dates).to eq([Date.new(2026, 2, 3), Date.new(2026, 5, 4)])
      expect(report.expense_lines.first.journal_entry.label).to eq("Marché")
    end
  end

  describe "sans compte de charge configuré" do
    it "ne totalise rien plutôt que de prendre toutes les charges" do
      spend(repas, 12_000)
      spend(autre_charge, 50_000)

      expect(report).not_to be_configured
      expect(report.expense_accounts).to eq([])
      expect(report.expense_lines).to eq([])
      expect(report.expenses_cents).to eq(0)
      expect(report).not_to be_any
    end
  end

  describe "l'encaissé" do
    let!(:mapping) { RevenueMapping.create!(category: "meals", general_account: compte_repas) }

    it "lit le compte de recette de la catégorie meals, jamais un autre" do
      cash_in(compte_repas, 45_000)
      cash_in(compte_locations, 300_000)

      expect(report.revenue_account).to eq(compte_repas)
      expect(report.collected_cents).to eq(45_000)
    end

    it "ignore un encaissement hors période" do
      cash_in(compte_repas, 45_000, on: Date.new(2026, 3, 20))
      cash_in(compte_repas, 15_000, on: Date.new(2026, 11, 4))

      restreint = described_class.new(from: Date.new(2026, 1, 1), to: Date.new(2026, 6, 30))

      expect(restreint.collected_cents).to eq(45_000)
    end

    # Un remboursement au client passe au débit du compte de recette : il
    # diminue l'encaissé.
    it "soustrait un mouvement débiteur du compte de recette" do
      cash_in(compte_repas, 45_000)
      post_simple_entry(entity: entity, debit_account: compte_repas, credit_account: banque,
                        amount_cents: 5_000, entry_date: Date.new(2026, 4, 10),
                        journal: "bank", label: "Remboursement")

      expect(report.collected_cents).to eq(40_000)
    end
  end

  describe "sans compte de recette rattaché à la catégorie meals" do
    it "rend zéro sans exploser" do
      cash_in(compte_repas, 45_000)

      expect(report.revenue_account).to be_nil
      expect(report).not_to be_revenue_account
      expect(report.collected_cents).to eq(0)
    end
  end
end
