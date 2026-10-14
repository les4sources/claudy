require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# La panne que cet écran répare n'est pas l'ignorance, c'est l'OUBLI. Ce qui
# compte donc, c'est qu'une étape repasse au rouge TOUTE SEULE quand la réalité
# change — une case cochée à la main aurait le même défaut que le tableur.
RSpec.describe Finance::MonthlyClose do
  include FinanceBuilders

  let(:month) { Date.new(2026, 8, 1) }
  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let(:revenue) { build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue") }
  let!(:cash_account) { build_cash_account(entity, bank_account) }
  let(:household) { Household.create!(name: "Chevêche", kind: "resident", moved_in_on: Date.new(2023, 1, 1)) }
  let!(:account) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }

  def steps = described_class.call(month: month)
  def step(key) = steps.find { |s| s.key == key }

  it "signale un mois sans aucun mouvement bancaire — un mois vide n'est pas un mois calme" do
    expect(step(:bank_lines)).to be_blocking
    expect(step(:bank_lines).detail).to match(/Aucune ligne/)
  end

  it "passe au vert quand les lignes sont là" do
    build_cash_entry(cash_account, entry_date: Date.new(2026, 8, 12))

    expect(step(:bank_lines)).to be_done
  end

  it "bloque tant qu'une ligne du mois reste à affecter" do
    build_cash_entry(cash_account, entry_date: Date.new(2026, 8, 12), amount_cents: 50_000)

    expect(step(:allocations)).to be_blocking
    expect(step(:allocations).detail).to match(/500\s?€/)
  end

  it "réclame un décompte pour tout compte au solde non nul" do
    account.account_entries.create!(entry_date: Date.new(2026, 8, 15), amount_cents: 12_000, label: "Bar")

    expect(step(:statements)).to be_blocking
    expect(step(:statements).detail).to include("Chevêche")
  end

  # Le solde qui compte est celui de la fin du mois arrêté. Le solde
  # d'aujourd'hui faisait réclamer en juillet un décompte pour une dette
  # d'octobre, et taisait un compte soldé depuis.
  describe "le solde regardé pour les décomptes" do
    it "ignore une dette née après le mois" do
      account.account_entries.create!(entry_date: Date.new(2026, 10, 3), amount_cents: 12_000, label: "Bar")

      expect(step(:statements)).to be_done
    end

    it "réclame le décompte d'un compte qui devait à la fin du mois, même soldé depuis" do
      account.account_entries.create!(entry_date: Date.new(2026, 8, 15), amount_cents: 12_000, label: "Bar")
      account.account_entries.create!(entry_date: Date.new(2026, 9, 10), amount_cents: -12_000, label: "Règlement")

      expect(step(:statements)).to be_blocking
      expect(step(:statements).detail).to include("Chevêche")
    end
  end

  describe "les charges récurrentes" do
    let(:other_household) { Household.create!(name: "Hulotte", kind: "resident", moved_in_on: Date.new(2023, 1, 1)) }
    let!(:other_account) { MemberAccount.create!(kind: "household", household: other_household, name: "Hulotte") }
    let!(:charge) do
      RecurringCharge.create!(applies_to: "resident_households", label: "Forfait commun", basis: "flat",
                              amount_cents: 5_000, flow: "charges", starts_on: Date.new(2026, 1, 1))
    end

    it "bloque tant qu'un foyer visé n'a pas sa ligne, même si un autre l'a" do
      Finance::GenerateRecurringCharges.new(month: month).run!
      AccountEntry.find_by(member_account: other_account).destroy!

      expect(step(:recurring)).to be_blocking
      expect(step(:recurring).detail).to include("1 compte(s)")
    end

    it "passe au vert quand chaque foyer a sa ligne" do
      Finance::GenerateRecurringCharges.new(month: month).run!

      expect(step(:recurring)).to be_done
    end

    # La reprise et le rattrapage de septembre 2026 ont posé une ligne
    # « Charges habitants » par foyer et par mois : ce mois-là est facturé.
    it "tient un foyer facturé à la main pour facturé" do
      [account, other_account].each do |compte|
        compte.account_entries.create!(entry_date: month.end_of_month, amount_cents: 28_000, label: "Charges habitants",
                                       kind: "recurring", flow: "charges", source: "reprise")
      end

      expect(step(:recurring)).to be_done
      expect(step(:recurring).detail).to include("2 foyer(s) facturé(s) à la main")
    end
  end

  # Le trou par lequel deux mois de bar sont restés impayés : le décompte
  # existait, il n'était simplement jamais parti.
  it "distingue « émis » de « envoyé »" do
    account.account_entries.create!(entry_date: Date.new(2026, 8, 15), amount_cents: 12_000, label: "Bar")
    Finance::IssueStatement.new(member_account: account, month: "2026-08").run!

    expect(step(:statements)).to be_done
    expect(step(:sent)).to be_blocking
    expect(step(:sent).detail).to match(/émis mais jamais envoyés/)
  end

  # Un sourcier peut légitimement payer le mois suivant : ça ne bloque pas
  # l'arrêté, mais ça doit se voir.
  it "montre les décomptes impayés sans bloquer l'arrêté" do
    account.account_entries.create!(entry_date: Date.new(2026, 8, 15), amount_cents: 12_000, label: "Bar")
    statement = Finance::IssueStatement.new(member_account: account, month: "2026-08").run!
    statement.update!(sent_at: Time.current, status: "sent")

    expect(step(:settlements)).to be_warning
    expect(step(:settlements)).not_to be_blocking
  end

  it "attrape une écriture déséquilibrée forcée en base" do
    post_simple_entry(entity: entity, debit_account: bank_account, credit_account: revenue,
                      entry_date: Date.new(2026, 8, 10))
    JournalLine.last.update_column(:credit_cents, 1)

    expect(step(:controls)).to be_blocking
  end

  it "voit le mois arrêté quand il l'est" do
    MonthClosing.create!(period_month: month, closed_at: Time.current, closed_by: "compta@les4sources.be")

    expect(step(:closing)).to be_done
    expect(step(:closing).detail).to include("compta@les4sources.be")
  end
end
