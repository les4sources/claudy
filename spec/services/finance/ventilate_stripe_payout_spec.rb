require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Le versement Stripe est un NET : la ventilation doit être une somme
# algébrique — recettes moins frais — dont le total vaut exactement ce qui est
# arrivé sur le compte.
RSpec.describe Finance::VentilateStripePayout do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:hebergement) { build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue") }
  let!(:frais) { build_general_account(code: "618000", name: "Frais bancaires", klass: 6, nature: "expense") }
  let!(:mapping) { RevenueMapping.create!(category: "lodging", general_account: hebergement) }
  let(:stripe_general) { build_general_account(code: "551000", name: "Stripe") }
  let(:cash_account) { CashAccount.create!(name: "Stripe", kind: "stripe", legal_entity: entity, general_account: stripe_general) }

  let(:payout) do
    StripePayout.create!(account_key: "claudy", cash_account: cash_account, stripe_id: "po_1",
                         amount_cents: 126_900, arrival_date: Date.new(2026, 8, 10))
  end

  it "ventile en somme algébrique dont le total vaut le net reçu" do
    StripeBalanceTransaction.create!(stripe_payout: payout, stripe_id: "txn_1", kind: "charge",
                                     gross_cents: 130_000, fee_cents: 3_100, net_cents: 126_900)

    lignes = described_class.new(payout: payout).run!

    expect(lignes.sum(&:amount_cents)).to eq(126_900)
    expect(lignes.find { |l| l.amount_cents.negative? }.general_account).to eq(frais)
  end

  # Les frais facturés à part — l'abonnement mensuel — ne portent pas de `fee` :
  # leur net EST le coût. Sans branche dédiée ils disparaissaient, et le total
  # ne refermait plus le versement. Constaté sur un jeu de données réaliste.
  it "compte les frais Stripe facturés à part, pas seulement les commissions" do
    payout.update!(amount_cents: 124_317)
    StripeBalanceTransaction.create!(stripe_payout: payout, stripe_id: "txn_1", kind: "charge",
                                     gross_cents: 130_000, fee_cents: 3_100, net_cents: 126_900)
    StripeBalanceTransaction.create!(stripe_payout: payout, stripe_id: "txn_2", kind: "stripe_fee",
                                     gross_cents: -2_583, fee_cents: 0, net_cents: -2_583,
                                     description: "Frais mensuels")

    lignes = described_class.new(payout: payout).run!

    expect(lignes.sum(&:amount_cents)).to eq(124_317)
    expect(lignes.map(&:label)).to include("Frais mensuels")
  end

  # La transaction de type `payout` est la contrepartie du versement lui-même :
  # la compter reviendrait à soustraire le versement de lui-même.
  it "ignore la transaction qui représente le versement lui-même" do
    StripeBalanceTransaction.create!(stripe_payout: payout, stripe_id: "txn_1", kind: "charge",
                                     gross_cents: 130_000, fee_cents: 3_100, net_cents: 126_900)
    StripeBalanceTransaction.create!(stripe_payout: payout, stripe_id: "txn_p", kind: "payout",
                                     gross_cents: -126_900, fee_cents: 0, net_cents: -126_900)

    expect(payout.reload).to be_balanced
    expect(described_class.new(payout: payout).run!.sum(&:amount_cents)).to eq(126_900)
  end

  # Un versement qu'on n'a pas fini de lire n'est pas un versement à
  # comptabiliser.
  it "refuse un versement dont les transactions ne le referment pas" do
    StripeBalanceTransaction.create!(stripe_payout: payout, stripe_id: "txn_1", kind: "charge",
                                     gross_cents: 100_000, fee_cents: 0, net_cents: 100_000)

    expect {
      described_class.new(payout: payout).run!
    }.to raise_error(described_class::Unbalanced, /Écart/)
  end

  # Sans ça, tout le coût d'encaissement atterrit sur l'administratif et
  # l'hébergement a l'air plus rentable qu'il ne l'est.
  it "fait suivre la commission au pôle qui l'a générée quand le paiement pointe un séjour" do
    technique = Team.create!(name: "Pôle Technique", kind: "economic")
    mapping.update!(team: technique)
    customer = Customer.create!(first_name: "Jeanne", last_name: "Dupont", email: "j@example.test")
    stay = Stay.create!(customer: customer, arrival_date: Date.new(2026, 8, 1),
                        departure_date: Date.new(2026, 8, 3), total_amount_cents: 130_000)
    payment = Payment.create!(stay_id: stay.id, amount_cents: 130_000, status: "paid", payment_method: "card")
    allow(Stays::DraftReconstructor).to receive(:call).with(stay).and_return(:draft)
    allow(PricingModel).to receive(:quote).with(:draft).and_return(
      instance_double(PricingModel::Quote, lodging_only_cents: 130_000, spaces_cents: 0, meals_cents: 0,
                                           camping_cents: 0, van_cents: 0, terrace_cents: 0,
                                           hamac_cents: 0, experiences_cents: 0)
    )

    StripeBalanceTransaction.create!(stripe_payout: payout, stripe_id: "txn_1", kind: "charge",
                                     gross_cents: 130_000, fee_cents: 3_100, net_cents: 126_900,
                                     payment: payment)

    lignes = described_class.new(payout: payout).run!
    commission = lignes.find { |l| l.amount_cents.negative? }

    expect(commission.team).to eq(technique)
    expect(lignes.sum(&:amount_cents)).to eq(126_900)
  end
end
