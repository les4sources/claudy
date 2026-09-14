require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #250, phase 1 — l'étape Stripe de l'arrêté du mois ne pose pas la même
# question selon le mode du compte.
RSpec.describe Finance::MonthlyClose, "son étape Stripe" do
  include FinanceBuilders

  let(:month) { Date.new(2026, 6, 1) }
  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2026) }
  let!(:stripe_general) { build_general_account(code: "551000", name: "Stripe") }
  let!(:fee_account) { build_general_account(code: "618000", name: "Frais bancaires", klass: 6, nature: "expense") }
  let!(:revenue_account) { build_general_account(code: "700100", name: "Ventes", klass: 7, nature: "revenue") }

  def step = described_class.call(month: month).find { |s| s.key == :stripe }

  def build_ledger_account
    CashAccount.create!(name: "Stripe Tranches de Vie", kind: "stripe", legal_entity: entity,
                        general_account: stripe_general, stripe_account_key: "tranche_de_vie",
                        stripe_mode: "ledger")
  end

  def build_charge(account, category: "pain")
    StripeBalanceTransaction.create!(
      cash_account: account, account_key: "tranche_de_vie", stripe_id: "txn_#{SecureRandom.hex(4)}",
      kind: "charge", gross_cents: 1_000, fee_cents: 29, net_cents: 971, category: category,
      occurred_at: Time.zone.local(2026, 6, 15)
    )
  end

  it "est verte quand aucun compte Stripe n'existe" do
    expect(step).to be_done
    expect(step.detail).to include("Aucun compte Stripe")
  end

  it "bloque quand une recette Stripe du mois attend sa correspondance de catégorie" do
    account = build_ledger_account
    Finance::RecordStripeTransaction.new(transaction: build_charge(account)).run!

    expect(step).to be_blocking
    expect(step.detail).to include("en attente")
    expect(step.action_path).to eq(:stripe_unallocated)
  end

  it "passe au vert dès que la correspondance existe" do
    account = build_ledger_account
    StripeCategoryMapping.create!(account_key: "tranche_de_vie", category: "pain",
                                  general_account: revenue_account)
    Finance::RecordStripeTransaction.new(transaction: build_charge(account)).run!

    expect(step).to be_done
    expect(step.detail).to include("Aucune ligne Stripe en attente")
  end

  # Une ligne d'un autre mois ne bloque pas l'arrêté de celui-ci.
  it "ne regarde que les lignes du mois" do
    account = build_ledger_account
    transaction = build_charge(account)
    transaction.update!(occurred_at: Time.zone.local(2026, 7, 15))
    Finance::RecordStripeTransaction.new(transaction: transaction).run!

    expect(step).to be_done
  end

  it "reste sur le contrôle par versement pour un compte en mode par versement" do
    account = CashAccount.create!(name: "Stripe Claudy", kind: "stripe", legal_entity: entity,
                                  general_account: stripe_general, stripe_account_key: "claudy")
    payout = StripePayout.create!(account_key: "claudy", cash_account: account, stripe_id: "po_001",
                                  amount_cents: 100_000, arrival_date: Date.new(2026, 6, 10),
                                  automatic: true)
    StripeBalanceTransaction.create!(stripe_payout: payout, cash_account: account,
                                     account_key: "claudy", stripe_id: "txn_x", kind: "charge",
                                     gross_cents: 50_000, fee_cents: 0, net_cents: 50_000,
                                     occurred_at: Time.zone.local(2026, 6, 9))

    expect(step).to be_blocking
    expect(step.detail).to include("ne se referment pas")
  end
end
