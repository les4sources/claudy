require "rails_helper"
require "rake"
require Rails.root.join("spec/support/finance_builders")

# Epic #250, phase 1 — le filet du mode grand livre. Une transaction importée
# sans ses lignes, un frais non affecté ou une référence en double ne se voient
# pas à l'œil nu : cette tâche est ce qui regarde à notre place.
RSpec.describe "accounting:verify_stripe_ledger" do
  include FinanceBuilders

  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  before do
    Rake::Task["accounting:verify_stripe_ledger"].reenable
    Rake::Task["accounting:verify_stripe_payouts"].reenable
    Rake::Task["accounting:verify_internal_transfers"].reenable
    Rake::Task["accounting:verify_allocations"].reenable
  end

  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2026) }
  let!(:stripe_general) { build_general_account(code: "551000", name: "Stripe") }
  let!(:bank_general) { build_general_account(code: "550000", name: "Banque") }
  let!(:fee_account) { build_general_account(code: "618000", name: "Frais bancaires", klass: 6, nature: "expense") }
  let!(:transfer_account) do
    build_general_account(code: GeneralAccount::INTERNAL_TRANSFER_CODE, name: "Virements internes")
  end
  let!(:revenue_account) { build_general_account(code: "700100", name: "Ventes épicerie", klass: 7, nature: "revenue") }

  let!(:cash_account) do
    CashAccount.create!(name: "Stripe Tranches de Vie", kind: "stripe", legal_entity: entity,
                        general_account: stripe_general, stripe_account_key: "tranche_de_vie",
                        stripe_mode: "ledger")
  end
  let!(:bank_account) { build_cash_account(entity, bank_general, name: "Triodos Fondation") }

  let!(:mapping) do
    StripeCategoryMapping.create!(account_key: "tranche_de_vie", category: "pain",
                                  general_account: revenue_account)
  end

  def run_task(name = "accounting:verify_stripe_ledger")
    original = $stdout
    $stdout = StringIO.new
    Rake::Task[name].invoke
    :ok
  rescue SystemExit
    :exit_1
  ensure
    $stdout = original
  end

  def build_charge(stripe_id: "txn_001", category: "pain")
    StripeBalanceTransaction.create!(
      cash_account: cash_account, account_key: "tranche_de_vie", stripe_id: stripe_id,
      kind: "charge", gross_cents: 1_000, fee_cents: 29, net_cents: 971,
      category: category, occurred_at: Time.zone.local(2026, 6, 15)
    )
  end

  def build_payout_transaction
    payout = StripePayout.create!(account_key: "tranche_de_vie", cash_account: cash_account,
                                  stripe_id: "po_001", amount_cents: 124_317, automatic: false,
                                  arrival_date: Date.new(2026, 6, 20))
    StripeBalanceTransaction.create!(
      cash_account: cash_account, account_key: "tranche_de_vie", stripe_payout: payout,
      stripe_id: "txn_payout", kind: "payout", gross_cents: -124_317, fee_cents: 0,
      net_cents: -124_317, occurred_at: Time.zone.local(2026, 6, 20)
    )
  end

  it "sort vide quand tout est en place" do
    Finance::RecordStripeTransaction.new(transaction: build_charge).run!
    Finance::RecordStripeTransaction.new(transaction: build_payout_transaction).run!

    expect(run_task).to eq(:ok)
  end

  it "sort vide quand aucun compte n'est en mode grand livre" do
    cash_account.update!(stripe_mode: "per_payout")

    expect(run_task).to eq(:ok)
  end

  it "crie quand une transaction importée n'a aucune ligne" do
    build_charge

    expect(run_task).to eq(:exit_1)
  end

  it "crie quand la commission d'un encaissement n'a pas de ligne" do
    transaction = build_charge
    # Seule la recette est entrée : la commission de 29 centimes n'a pas de ligne,
    # donc elle a disparu du coût d'encaissement sans que rien ne le dise.
    CashEntry.create!(cash_account: cash_account, source: transaction,
                      entry_date: Date.new(2026, 6, 15), amount_cents: 1_000,
                      label: "pain", external_ref: "stripe:txn_001:gross")

    expect(run_task).to eq(:exit_1)
  end

  it "crie quand la ligne d'un versement n'est pas affectée sur le compte de virements internes" do
    transaction = build_payout_transaction
    # La ligne existe, mais affectée ailleurs : le versement ne se retrouve plus
    # en face de sa ligne bancaire, et le 580000 ne se solde plus à zéro.
    ligne = CashEntry.create!(cash_account: cash_account, source: transaction,
                              entry_date: Date.new(2026, 6, 20), amount_cents: -124_317,
                              label: "Versement Stripe", external_ref: "stripe:txn_payout:net")
    ligne.cash_allocations.create!(general_account: fee_account, legal_entity: entity,
                                   amount_cents: -124_317)

    expect(run_task).to eq(:exit_1)
  end

  it "crie quand la ligne d'un versement ne porte pas le versement en document" do
    transaction = build_payout_transaction
    ligne = CashEntry.create!(cash_account: cash_account, source: transaction,
                              entry_date: Date.new(2026, 6, 20), amount_cents: -124_317,
                              label: "Versement Stripe", external_ref: "stripe:txn_payout:net")
    ligne.cash_allocations.create!(general_account: transfer_account, legal_entity: entity,
                                   amount_cents: -124_317)

    expect(run_task).to eq(:exit_1)
  end

  # Les deux invariants existants doivent rester verts en présence d'un
  # versement importé en mode grand livre et rapproché côté banque.
  it "laisse verify_internal_transfers et verify_allocations verts après un aller-retour complet" do
    Finance::RecordStripeTransaction.new(transaction: build_charge).run!
    Finance::RecordStripeTransaction.new(transaction: build_payout_transaction).run!

    payout = StripePayout.find_by(stripe_id: "po_001")
    ligne_banque = CashEntry.create!(cash_account: bank_account, entry_date: Date.new(2026, 6, 21),
                                     amount_cents: 124_317, label: "Versement Stripe")
    ligne_banque.cash_allocations.create!(general_account: transfer_account, legal_entity: entity,
                                          amount_cents: 124_317, document: payout)
    Accounting::PostCashEntry.new(cash_entry: ligne_banque).run!

    expect(run_task("accounting:verify_internal_transfers")).to eq(:ok)
    expect(run_task("accounting:verify_allocations")).to eq(:ok)
    expect(run_task("accounting:verify_stripe_payouts")).to eq(:ok)
  end

  # Un versement de compte `ledger` n'a pas de composantes : le contrôle par
  # versement n'a rien à y vérifier et ne doit pas crier.
  it "laisse verify_stripe_payouts ignorer un versement de compte grand livre" do
    build_payout_transaction

    expect(run_task("accounting:verify_stripe_payouts")).to eq(:ok)
  end
end
