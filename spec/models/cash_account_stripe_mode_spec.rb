require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #250, phase 1 — le mode de lecture d'un compte Stripe.
RSpec.describe CashAccount, "son mode Stripe", type: :model do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let(:general) { build_general_account(code: "551000", name: "Stripe") }

  it "naît en mode par versement" do
    account = CashAccount.create!(name: "Stripe Claudy", kind: "stripe", legal_entity: entity,
                                  general_account: general)

    expect(account.stripe_mode).to eq("per_payout")
    expect(account).to be_per_payout
    expect(account).not_to be_ledger
  end

  it "refuse un mode hors liste" do
    account = CashAccount.new(name: "Stripe X", kind: "stripe", legal_entity: entity,
                              general_account: general, stripe_mode: "magique")

    expect(account).not_to be_valid
  end

  # Le mode ne veut rien dire hors d'un compte Stripe : un compte bancaire porte
  # la valeur par défaut et personne ne doit la lire.
  it "ne rend jamais `ledger?` vrai pour un compte bancaire" do
    bank = build_cash_account(entity, build_general_account(code: "550000", name: "Banque"))
    bank.update_column(:stripe_mode, "ledger")

    expect(bank.reload).not_to be_ledger
  end

  it "se laisse lister par le scope des comptes en grand livre" do
    ledger = CashAccount.create!(name: "Stripe Tranches de Vie", kind: "stripe", legal_entity: entity,
                                 general_account: general, stripe_mode: "ledger")
    CashAccount.create!(name: "Stripe Claudy", kind: "stripe", legal_entity: entity,
                        general_account: build_general_account(code: "551100", name: "Stripe 2"))

    expect(CashAccount.stripe_ledger.to_a).to eq([ledger])
  end
end
