require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #250, phase 1 — la synchronisation d'un compte à versements MANUELS.
#
# Constaté en production le 2026-09-07 : Stripe refuse
# `BalanceTransaction.list(payout: …)` sur ce genre de compte, et le rake
# s'arrêtait net. Ici on lit le solde, pas les versements.
RSpec.describe Stripe::SyncPayouts, "en mode grand livre" do
  include FinanceBuilders

  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2026) }
  let!(:stripe_general) { build_general_account(code: "551000", name: "Stripe") }
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

  let(:payouts) do
    [{ id: "po_001", amount: 124_317, currency: "eur", status: "paid", automatic: false,
       arrival_date: Date.new(2026, 6, 20) }]
  end

  let(:transactions) do
    [{ id: "txn_pain", type: "charge", amount: 1_000, fee: 29, net: 971, description: "Vente",
       created: Time.zone.local(2026, 6, 15), available_on: Date.new(2026, 6, 17),
       category: "pain", source_id: "ch_001" },
     { id: "txn_legumes", type: "charge", amount: 2_500, fee: 55, net: 2_445, description: "Vente",
       created: Time.zone.local(2026, 6, 16), available_on: Date.new(2026, 6, 18),
       category: "legumes", source_id: "ch_002" },
     { id: "txn_frais", type: "stripe_fee", amount: -2_583, fee: 0, net: -2_583,
       description: "Frais mensuels", created: Time.zone.local(2026, 6, 30), category: nil },
     { id: "txn_payout", type: "payout", amount: -124_317, fee: 0, net: -124_317,
       description: "Versement", created: Time.zone.local(2026, 6, 20), category: nil,
       source_id: "po_001" }]
  end

  let(:client) do
    stub = double("client")
    allow(stub).to receive(:payouts).with(since: anything).and_return(payouts)
    allow(stub).to receive(:balance_transactions_since).with(since: anything).and_return(transactions)
    stub
  end

  def sync(apply: false)
    described_class.new(account_key: :tranche_de_vie, since: Date.new(2026, 1, 1),
                        apply: apply, client: client).run!
  end

  it "n'écrit rien en dry-run mais annonce les catégories rencontrées" do
    rapport = nil
    expect { rapport = sync }.to change { CashEntry.count }.by(0)

    expect(rapport[:mode]).to eq("ledger")
    expect(rapport[:created_payouts]).to eq(1)
    expect(rapport[:created_transactions]).to eq(4)

    categories = rapport[:categories].index_by { |row| row[:category] }
    expect(categories["pain"]).to include(count: 1, amount_cents: 1_000, mapped: false)
    expect(categories["legumes"]).to include(count: 1, amount_cents: 2_500, mapped: false)
    expect(rapport[:messages].join).to match(/sans correspondance.*pain/)
  end

  it "n'interroge jamais les transactions d'un versement" do
    expect(client).not_to receive(:balance_transactions)

    sync(apply: true)
  end

  it "importe versements et transactions, et en fait des lignes de trésorerie" do
    sync(apply: true)

    expect(StripePayout.count).to eq(1)
    expect(StripePayout.first.automatic).to be(false)
    expect(StripeBalanceTransaction.count).to eq(4)
    # Deux lignes par encaissement, une pour les frais, une pour le versement.
    expect(CashEntry.where(cash_account: cash_account).count).to eq(6)
  end

  it "affecte les recettes dont la catégorie a une correspondance, laisse les autres en attente" do
    StripeCategoryMapping.create!(account_key: "tranche_de_vie", category: "pain",
                                  general_account: revenue_account)
    sync(apply: true)

    expect(CashEntry.find_by(external_ref: "stripe:txn_pain:gross").status).to eq("allocated")
    expect(CashEntry.find_by(external_ref: "stripe:txn_legumes:gross").status).to eq("pending")
  end

  it "fait du versement un virement interne portant le versement en document" do
    sync(apply: true)

    ligne = CashEntry.find_by(external_ref: "stripe:txn_payout:net")
    expect(ligne.amount_cents).to eq(-124_317)
    allocation = ligne.cash_allocations.sole
    expect(allocation.general_account).to eq(transfer_account)
    expect(allocation.document).to eq(StripePayout.find_by(stripe_id: "po_001"))
  end

  it "rejoue sans rien recréer" do
    sync(apply: true)

    expect { sync(apply: true) }.to change { CashEntry.count }.by(0)
    expect { sync(apply: true) }.to change { StripeBalanceTransaction.count }.by(0)
    expect(StripePayout.count).to eq(1)
  end

  it "signale les catégories déjà couvertes comme telles" do
    StripeCategoryMapping.create!(account_key: "tranche_de_vie", category: "pain",
                                  general_account: revenue_account)
    StripeCategoryMapping.create!(account_key: "tranche_de_vie", category: "legumes",
                                  general_account: revenue_account)

    rapport = sync
    expect(rapport[:categories]).to all(include(mapped: true))
    expect(rapport[:messages]).to be_empty
  end
end

# Le cas qui a fait tomber la production : un compte manuel resté en mode par
# versement. Ça ne doit pas lever — ça doit se dire.
RSpec.describe Stripe::SyncPayouts, "devant un versement manuel en mode par versement" do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:stripe_general) { build_general_account(code: "551000", name: "Stripe") }
  let!(:cash_account) do
    CashAccount.create!(name: "Stripe Tranches de Vie", kind: "stripe", legal_entity: entity,
                        general_account: stripe_general, stripe_account_key: "tranche_de_vie")
  end

  let(:payouts) do
    [{ id: "po_001", amount: 124_317, currency: "eur", status: "paid", automatic: false,
       arrival_date: Date.new(2026, 6, 20) }]
  end
  let(:client) do
    stub = double("client")
    allow(stub).to receive(:payouts).with(since: anything).and_return(payouts)
    stub
  end

  it "n'importe rien, ne lève pas, et dit quoi faire" do
    rapport = nil

    expect {
      rapport = described_class.new(account_key: :tranche_de_vie, since: Date.new(2026, 1, 1),
                                    apply: true, client: client).run!
    }.to change { StripePayout.count }.by(0)

    expect(rapport[:created_payouts]).to eq(0)
    expect(rapport[:messages].join).to include("versement(s) manuel(s)")
    expect(rapport[:messages].join).to include("stripe_mode")
  end

  it "n'interroge pas les transactions du versement manuel" do
    expect(client).not_to receive(:balance_transactions)

    described_class.new(account_key: :tranche_de_vie, since: Date.new(2026, 1, 1),
                        apply: true, client: client).run!
  end
end
