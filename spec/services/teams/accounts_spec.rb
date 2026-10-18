require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Les comptes d'un pôle pour une année (Michael, 2026-10-18) : santé, budget,
# dépenses à valider.
RSpec.describe Teams::Accounts do
  include FinanceBuilders

  let(:team) { Team.create!(name: "Pôle Cuisine", kind: "analytic") }
  let(:other_team) { Team.create!(name: "Pôle Accueil", kind: "economic") }
  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2026) }
  let(:bank) { build_general_account(code: "550000", name: "Banque", klass: 5, nature: "asset") }
  let(:sales) { build_general_account(code: "700000", name: "Ventes", klass: 7, nature: "revenue") }
  let(:supplies) { build_general_account(code: "600000", name: "Achats", klass: 6, nature: "expense") }
  # Le 1er juillet : à peu près la moitié de l'année est passée.
  let(:today) { Date.new(2026, 7, 1) }

  subject(:accounts) { described_class.new(team: team, year: 2026, today: today) }

  def revenue(amount_cents, on:, for_team: team)
    Accounting::PostDocument.new(
      legal_entity: entity, journal: "sales", entry_date: on, label: "Vente",
      lines: [{ account: bank, debit_cents: amount_cents },
              { account: sales, credit_cents: amount_cents, team: for_team }]
    ).run!
  end

  def expense(amount_cents, on:, for_team: team)
    Accounting::PostDocument.new(
      legal_entity: entity, journal: "purchases", entry_date: on, label: "Achat",
      lines: [{ account: supplies, debit_cents: amount_cents, team: for_team },
              { account: bank, credit_cents: amount_cents }]
    ).run!
  end

  describe "le résultat" do
    it "somme les produits et les charges du pôle sur l'année" do
      revenue(120_000, on: Date.new(2026, 3, 1))
      expense(45_000, on: Date.new(2026, 4, 1))

      expect(accounts.totals.revenue_cents).to eq(120_000)
      expect(accounts.totals.expense_cents).to eq(45_000)
      expect(accounts.net_cents).to eq(75_000)
    end

    it "ignore les écritures d'un autre pôle et des autres années" do
      build_fiscal_year(entity, year: 2025)
      revenue(120_000, on: Date.new(2026, 3, 1), for_team: other_team)
      revenue(90_000, on: Date.new(2025, 6, 1))

      expect(accounts.totals.revenue_cents).to eq(0)
    end

    it "additionne les pôles qu'il regroupe" do
      child = Team.create!(name: "Boulangerie", kind: "analytic", parent: team)
      revenue(10_000, on: Date.new(2026, 3, 1))
      revenue(30_000, on: Date.new(2026, 3, 2), for_team: child)

      expect(accounts.totals.revenue_cents).to eq(40_000)
      expect(accounts.sub_team_rows.map { |row| [row.team, row.totals.revenue_cents] })
        .to eq([[team, 10_000], [child, 30_000]])
    end

    it "compare à la même date l'an dernier, pas à l'année entière" do
      build_fiscal_year(entity, year: 2025)
      revenue(20_000, on: Date.new(2025, 3, 1))
      revenue(50_000, on: Date.new(2025, 9, 1))

      expect(accounts.previous_totals.revenue_cents).to eq(20_000)
    end

    it "range les écritures par mois" do
      revenue(20_000, on: Date.new(2026, 3, 1))
      expense(5_000, on: Date.new(2026, 3, 20))

      march = accounts.months[2]
      expect(march.month).to eq(Date.new(2026, 3, 1))
      expect([march.revenue_cents, march.expense_cents]).to eq([20_000, 5_000])
      expect(accounts.months.size).to eq(12)
    end
  end

  describe "ce qui n'est pas encore au grand livre" do
    let(:supplier) { ThirdParty.create!(name: "Colruyt", kind: "supplier") }

    def invoice(status:, amount_cents: 12_000, for_team: team, validation_team: nil)
      record = PurchaseInvoice.create!(legal_entity: entity, third_party: supplier, number: "F-#{rand(100_000)}",
                                       issued_on: Date.new(2026, 6, 1), total_cents: amount_cents,
                                       requires_validation: validation_team.present?, validation_team: validation_team)
      record.purchase_invoice_lines.create!(general_account: supplies, team: for_team, amount_cents: amount_cents)
      record.update_column(:status, status)
      record
    end

    it "compte les factures pas encore validées et les notes de frais pas encore traitées" do
      invoice(status: "to_validate", amount_cents: 12_000)
      invoice(status: "to_process", amount_cents: 3_000)
      invoice(status: "to_validate", amount_cents: 99_000, for_team: other_team)
      report = ExpenseReport.create!(human: Human.create!(name: "Steph"), legal_entity: entity,
                                     submitted_on: Date.new(2026, 6, 2))
      report.expense_lines.create!(spent_on: Date.new(2026, 6, 2), label: "Farine", amount_cents: 2_500,
                                   general_account: supplies, team: team, receipt_on_paper: true)
      expense(10_000, on: Date.new(2026, 2, 1))

      expect(accounts.upcoming_invoices_cents).to eq(15_000)
      expect(accounts.upcoming_expense_reports_cents).to eq(2_500)
      expect(accounts.projected_net_cents).to eq(-10_000 - 17_500)
    end

    it "liste les factures qui attendent le oui du pôle" do
      waiting = invoice(status: "to_validate", validation_team: team)
      invoice(status: "to_validate", validation_team: other_team)
      invoice(status: "to_pay", validation_team: team)

      expect(accounts.invoices_to_validate).to eq([waiting])
      expect(accounts.invoices_to_validate_cents).to eq(12_000)
    end
  end

  describe "la santé" do
    it "ne juge rien quand il n'y a ni budget ni chiffre" do
      expect(accounts.health.level).to eq(:none)
    end

    it "sans budget, ne juge que le résultat" do
      expense(10_000, on: Date.new(2026, 2, 1))

      expect(accounts.health.level).to eq(:alert)
      expect(accounts.health.label).to eq("En déficit")
    end

    context "avec un budget" do
      # Un service support : 0 de produits, 10 000 € de charges prévues.
      let!(:budget) { TeamBudget.create!(team: team, year: 2026, revenue_cents: 0, expense_cents: 1_000_000) }

      it "est dans le budget quand les charges suivent le rythme de l'année" do
        expense(400_000, on: Date.new(2026, 3, 1))

        expect(accounts.health.level).to eq(:good)
      end

      it "est à surveiller un peu au-dessus du rythme, hors budget bien au-dessus" do
        expense(550_000, on: Date.new(2026, 3, 1))
        expect(accounts.health.level).to eq(:watch)

        expense(200_000, on: Date.new(2026, 4, 1))
        expect(described_class.new(team: team, year: 2026, today: today).health.level).to eq(:alert)
      end

      it "prévoit le résultat au prorata de l'année écoulée" do
        expect(accounts.elapsed_ratio).to be_within(0.01).of(0.5)
        expect(accounts.expected_net_cents).to be_within(10_000).of(-500_000)
      end
    end
  end

  describe ".snapshots" do
    it "résume chaque pôle de l'annuaire, enfants compris" do
      child = Team.create!(name: "Boulangerie", kind: "analytic", parent: team)
      expense(10_000, on: Date.new(2026, 3, 1), for_team: child)
      TeamBudget.create!(team: team, year: 2026, expense_cents: 40_000)

      snapshots = described_class.snapshots([team, child, other_team], year: 2026)

      expect(snapshots[team.id].expense_cents).to eq(10_000)
      expect(snapshots[team.id].budget_percent).to eq(25)
      expect(snapshots[child.id].budget_percent).to be_nil
      expect(snapshots[other_team.id].net_cents).to eq(0)
    end
  end

  describe "les affectations de trésorerie" do
    let(:cash_account) { build_cash_account(entity, bank) }

    it "rend celles du pôle sur l'année, la plus récente d'abord" do
      old = allocate(build_cash_entry(cash_account, amount_cents: 10_000, entry_date: Date.new(2026, 2, 1)),
                     account: sales, amount_cents: 10_000, entity: entity, team: team)
      recent = allocate(build_cash_entry(cash_account, amount_cents: 20_000, entry_date: Date.new(2026, 8, 1)),
                        account: sales, amount_cents: 20_000, entity: entity, team: team)
      allocate(build_cash_entry(cash_account, amount_cents: 30_000, entry_date: Date.new(2026, 9, 1)),
               account: sales, amount_cents: 30_000, entity: entity, team: other_team)

      expect(accounts.recent_allocations.map(&:id)).to eq([recent.id, old.id])
    end

    it "dit combien de lignes attendent encore d'être affectées, tous pôles confondus" do
      build_cash_entry(cash_account, amount_cents: 5_000)

      expect(accounts.pending_entries_count).to eq(1)
      expect(accounts.incomplete?).to be(true)
    end
  end
end
