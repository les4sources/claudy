require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# « Peut-on dépenser ? » (Michael, 2026-10-13) : le solde en banque n'est pas
# ce qu'on peut dépenser. Ce qui est dû et ce qui a été prêté en sont retirés.
RSpec.describe Finance::SpendingVerdict do
  include FinanceBuilders

  let(:today) { Date.new(2026, 10, 13) }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_general) { build_general_account(code: "550000", name: "Triodos") }
  let!(:bank) { build_cash_account(entity, bank_general, name: "Triodos") }
  let(:prets) { build_general_account(code: "174004", name: "Prêt court terme Sourciers", klass: 1, nature: "liability") }

  subject(:verdict) { described_class.new(legal_entity: entity, today: today) }

  def coda_statement(account, balance_cents:, on: Date.new(2026, 10, 13))
    import = CodaImport.create!(filename: "releve-#{on}-#{SecureRandom.hex(2)}.cod", sha256: SecureRandom.hex(32), content: "x")
    CodaStatement.create!(coda_import: import, cash_account: account, sequence_number: SecureRandom.hex(2),
                          period_year: on.year, old_balance_cents: 0, new_balance_cents: balance_cents,
                          new_balance_date: on)
  end

  def pret(cents)
    post_simple_entry(entity: entity, debit_account: bank_general, credit_account: prets, amount_cents: cents,
                      entry_date: Date.new(2026, 6, 10))
  end

  def charge_fixe(cents)
    RecurringExpense.create!(legal_entity: entity, label: "Loyer", amount_cents: cents, frequency: "monthly",
                             first_due_on: Date.new(2026, 1, 27))
  end

  it "dit non quand l'argent en banque a été prêté" do
    coda_statement(bank, balance_cents: 5_624_180)
    pret(6_000_000)

    expect(verdict.verdict).to eq("non")
    expect(verdict.loans_cents).to eq(6_000_000)
    expect(verdict.margin_cents).to eq(-375_820)
    expect(verdict.headline).to eq("Non : pas de dépense nouvelle.")
    expect(verdict.reason).to include("il manque 3 758 €")
  end

  # Les certificats immobiliers se rendent sur des années : les retirer de la
  # marge des 90 jours faisait dire « il manque 717 000 € » (2026-10-16).
  it "ne retire pas un prêt à long terme, mais le dit" do
    certificats = build_general_account(code: "174001", name: "Certificat immobilier", klass: 1, nature: "liability")
    certificats.update!(long_term: true)
    coda_statement(bank, balance_cents: 5_624_180)
    post_simple_entry(entity: entity, debit_account: bank_general, credit_account: certificats, amount_cents: 75_000_000,
                      entry_date: Date.new(2026, 2, 28))
    pret(800_000)

    expect(verdict.loans_cents).to eq(800_000)
    expect(verdict.long_term_loans_cents).to eq(75_000_000)
    expect(verdict.margin_cents).to eq(4_824_180)
    expect(verdict.reserves.join).to include("Prêts à long terme : 750 000 € restent dus, hors de la marge")
  end

  it "ne laisse pas un compte de prêt débiteur effacer ce qu'on doit aux autres" do
    noire = build_general_account(code: "174003", name: "Prêt SA Noire", klass: 1, nature: "liability")
    coda_statement(bank, balance_cents: 5_624_180)
    pret(800_000)
    post_simple_entry(entity: entity, debit_account: noire, credit_account: bank_general, amount_cents: 2_000_000,
                      entry_date: Date.new(2026, 3, 1))

    expect(verdict.loans_cents).to eq(800_000)
    expect(verdict.reserves.join).to include("174003 Prêt SA Noire : solde débiteur de 20 000 €", "à vérifier")
  end

  # En prod, des remboursements sont passés sans tiers sur le compte d'un prêt
  # nommé : par prêteur, le prêt restait entier et le remboursement disparaissait.
  it "solde un prêt nommé par un remboursement sans tiers du même compte" do
    gaelle = ThirdParty.create!(code: "DEFAYS", name: "Gaëlle de Fays", kind: "supplier")
    coda_statement(bank, balance_cents: 5_624_180)
    entry = build_cash_entry(bank, amount_cents: 1_000_000, entry_date: Date.new(2026, 4, 7), label: "Prêt")
    entry.cash_allocations.create!(general_account: prets, amount_cents: 1_000_000, legal_entity: entity, third_party: gaelle)
    Accounting::PostCashEntry.new(cash_entry: entry).run!
    post_simple_entry(entity: entity, debit_account: prets, credit_account: bank_general, amount_cents: 600_000,
                      entry_date: Date.new(2026, 9, 1))

    expect(verdict.loans_cents).to eq(400_000)
    expect(verdict.reserves.join).not_to include("solde débiteur")
  end

  it "dit oui, et combien, quand il reste plus qu'un mois de charges fixes une fois tout payé" do
    coda_statement(bank, balance_cents: 1_000_000)
    charge_fixe(100_000)

    # 10 000 € − trois loyers dans les 90 jours = 7 000 € ; un loyer reste de côté.
    expect(verdict.margin_cents).to eq(700_000)
    expect(verdict.reserve_cents).to eq(100_000)
    expect(verdict.verdict).to eq("oui")
    expect(verdict.spendable_cents).to eq(600_000)
    expect(verdict.headline).to eq("Oui, jusqu'à 6 000 €.")
  end

  it "demande de la prudence quand la marge ne couvre pas un mois de charges fixes" do
    coda_statement(bank, balance_cents: 350_000)
    charge_fixe(100_000)

    expect(verdict.margin_cents).to eq(50_000)
    expect(verdict.verdict).to eq("prudence")
    expect(verdict.spendable_cents).to eq(0)
  end

  it "ne tranche pas sans solde vérifié" do
    build_cash_entry(bank, amount_cents: 1_000_000, entry_date: Date.new(2026, 10, 1))

    expect(verdict.verdict).to eq("inconnu")
    expect(verdict.reserves.join).to include("Triodos", "jamais vérifié")
  end

  it "prévient que des lignes « À affecter » peuvent cacher un prêt" do
    coda_statement(bank, balance_cents: 1_000_000)
    build_cash_entry(bank, amount_cents: 2_000_000, entry_date: Date.new(2026, 6, 10), label: "Pret tresorerie")

    expect(verdict.reserves.first).to start_with("1 ligne(s) « À affecter »").and include("un prêt ou une dette")
  end

  it "donne un verdict par entité qui a un compte, la Fondation d'abord" do
    srl = build_legal_entity(name: "Domaine d'Ahinvaux SRL", form: "srl")
    build_cash_account(srl, build_general_account(code: "550100", name: "Beobank"), name: "Beobank")
    build_legal_entity(name: "Sans compte", form: "simple_company")

    expect(described_class.for_all(today: today).map { |v| v.entity.name })
      .to eq(["Fondation Les 4 Sources", "Domaine d'Ahinvaux SRL"])
  end
end
