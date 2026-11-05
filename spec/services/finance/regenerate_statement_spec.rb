require "rails_helper"

# 2026-11-02 — les décomptes d'octobre 2026 émis trop tôt, avant le bar et les
# charges du 31, et que rien ne permettait de reprendre.
RSpec.describe Finance::RegenerateStatement do
  let(:household) { Household.create!(name: "Chevêche", kind: "resident", moved_in_on: Date.new(2023, 1, 1)) }
  let(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

  def add_entry(date, cents, **attrs)
    account.account_entries.create!(entry_date: date, amount_cents: cents, label: "Ligne", **attrs)
  end

  def issue(month) = Finance::IssueStatement.new(member_account: account, month: month).run!

  def regenerate(statement, **options) = described_class.new(statement: statement, whodunnit: "test", **options).run!

  let!(:octobre) do
    add_entry(Date.new(2026, 10, 8), 10_000)
    issue("2026-10")
  end

  before do
    add_entry(Date.new(2026, 10, 31), 2_500, flow: "bar")   # le bar, posé après l'émission
    add_entry(Date.new(2026, 9, 30), -34_500)                # un règlement rapproché après coup
  end

  it "remplace le décompte par un décompte qui colle au grand livre" do
    expect(octobre.ledger_gap_cents).not_to eq(0)

    result = regenerate(octobre)

    expect(result.previous[:closing_balance_cents]).to eq(10_000)
    expect(result.statement.closing_balance_cents).to eq(account.reload.balance_cents)
    expect(result.statement.ledger_gap_cents).to eq(0)
    expect(result.statement.account_entries.count).to eq(2)
    expect(AccountStatement.for_month(Date.new(2026, 10, 1)).count).to eq(1)
  end

  it "garde l'ancien décompte à la corbeille, avec sa trace" do
    regenerate(octobre)

    ancien = AccountStatement.with_deleted { AccountStatement.find(octobre.id) }
    expect(ancien.deleted_at).to be_present
    expect(ancien.closing_balance_cents).to eq(10_000)
    expect(ancien.versions.last.whodunnit).to eq("test")
  end

  it "annule sans réémettre : les lignes sont déverrouillées" do
    regenerate(octobre, reissue: false)

    expect(AccountStatement.for_month(Date.new(2026, 10, 1))).to be_empty
    expect(account.account_entries.reload.none?(&:locked?)).to be(true)
  end

  it "ne touche à rien si la réémission est refusée" do
    RecurringCharge.create!(label: "Charges habitants", basis: "flat", amount_cents: 32_500, flow: "charges",
                            applies_to: "resident_households", starts_on: Date.new(2023, 1, 1))

    expect { regenerate(octobre) }.to raise_error(Finance::IssueStatement::RecurringChargesMissing)
    expect(octobre.reload.deleted_at).to be_nil
    expect(octobre.account_entries.count).to eq(1)
    expect(octobre.account_entries.first).to be_locked
  end

  describe "refus" do
    it "un décompte déjà envoyé" do
      octobre.update!(status: "sent", sent_at: Time.current)

      expect { regenerate(octobre) }.to raise_error(described_class::Refused, /déjà été envoyé/)
    end

    it "un décompte déjà relancé" do
      octobre.update!(reminders_count: 1)

      expect { regenerate(octobre) }.to raise_error(described_class::Refused, /relancé/)
    end

    it "un décompte réglé" do
      octobre.update!(status: "settled")

      expect { regenerate(octobre) }.to raise_error(described_class::Refused, /réglé/)
    end

    it "un décompte qui n'est pas le dernier du compte" do
      AccountStatement.create!(member_account: account, period_month: Date.new(2026, 11, 1), status: "issued",
                               issued_at: Time.current, opening_balance_cents: 10_000, closing_balance_cents: 10_000)

      expect { regenerate(octobre) }.to raise_error(described_class::Refused, /plus récent/)
    end
  end
end
