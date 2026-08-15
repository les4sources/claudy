require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Le client est injecté : interroger le compte Stripe de production, ou demander
# les clés d'un second compte, n'est pas une décision qui se prend au fil d'une
# implémentation. Ces specs tournent sur des jeux de données construits d'après
# le format documenté des objets Stripe.
RSpec.describe Stripe::SyncPayouts do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let(:stripe_account_general) { build_general_account(code: "551000", name: "Stripe") }
  let!(:cash_account) do
    CashAccount.create!(name: "Stripe Claudy", kind: "stripe", legal_entity: entity,
                        general_account: stripe_account_general)
  end

  let(:payouts) do
    [{ id: "po_001", amount: 124_317, currency: "eur", status: "paid",
       arrival_date: Date.new(2026, 8, 10) }]
  end
  let(:transactions) do
    [{ id: "txn_001", type: "charge", amount: 130_000, fee: 3_100, net: 126_900,
       description: "Séjour", created: Time.zone.local(2026, 8, 8) },
     { id: "txn_002", type: "stripe_fee", amount: -2_583, fee: 0, net: -2_583,
       description: "Frais mensuels", created: Time.zone.local(2026, 8, 9) }]
  end
  let(:client) do
    double("client", payouts: payouts, balance_transactions: transactions).tap do |stub|
      allow(stub).to receive(:payouts).with(since: anything).and_return(payouts)
      allow(stub).to receive(:balance_transactions).with(payout_id: "po_001").and_return(transactions)
    end
  end

  def sync(apply: false)
    described_class.new(account_key: :claudy, since: Date.new(2026, 1, 1), apply: apply, client: client).run!
  end

  # Un rake qui écrit sans qu'on l'ait demandé est un rake qu'on n'ose plus
  # lancer.
  it "n'écrit rien en dry-run mais annonce ce qui serait créé" do
    rapport = nil
    expect { rapport = sync }.not_to change { StripePayout.count }

    expect(rapport[:created_payouts]).to eq(1)
    expect(rapport[:created_transactions]).to eq(2)
  end

  it "écrit le versement et ses transactions avec APPLY" do
    expect { sync(apply: true) }.to change { StripePayout.count }.by(1)
                                .and change { StripeBalanceTransaction.count }.by(2)

    payout = StripePayout.last
    expect(payout.amount_cents).to eq(124_317)
    expect(payout.cash_account).to eq(cash_account)
    expect(payout.transactions_net_cents).to eq(124_317)
    expect(payout).to be_balanced
  end

  it "ne réimporte pas un versement déjà connu" do
    sync(apply: true)

    expect { sync(apply: true) }.not_to change { StripePayout.count }
  end

  # L'enregistrer puis le sauter à la relance le figerait incomplet pour
  # toujours, et il fausserait le coût d'encaissement sans que rien ne le dise.
  it "n'importe PAS un versement dont les transactions ne le referment pas" do
    transactions.pop

    rapport = nil
    expect { rapport = sync(apply: true) }.not_to change { StripePayout.count }
    expect(rapport[:messages].join).to match(/ignoré/)
  end

  it "reconnaît les types Stripe hors carte comme des recettes" do
    transactions.first[:type] = "payment"
    sync(apply: true)

    expect(StripeBalanceTransaction.find_by(stripe_id: "txn_001").kind).to eq("payment")
    expect(StripePayout.last.gross_cents).to eq(130_000)
  end

  it "rattache le versement au compte de trésorerie de SA clé" do
    autre = CashAccount.create!(name: "Stripe TdV", kind: "stripe", legal_entity: entity,
                                general_account: stripe_account_general,
                                stripe_account_key: "tranche_de_vie")
    cash_account.update!(stripe_account_key: "claudy")

    sync(apply: true)

    expect(StripePayout.last.cash_account).to eq(cash_account)
    expect(StripePayout.where(cash_account: autre).count).to eq(0)
  end

  it "range un type inconnu dans « other » plutôt que d'échouer" do
    transactions.first[:type] = "quelque_chose_de_nouveau"
    sync(apply: true)

    expect(StripeBalanceTransaction.find_by(stripe_id: "txn_001").kind).to eq("other")
  end
end
