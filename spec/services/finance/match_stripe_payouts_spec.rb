require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #250, phase 2 — proposer un versement Stripe sur une ligne bancaire.
#
# L'invariant B4 : ce service PROPOSE, il n'écrit jamais. Le rapprochement se
# faisait jusqu'ici de tête, à l'euro près, dans l'interface Stripe.
RSpec.describe Finance::MatchStripePayouts do
  include FinanceBuilders

  let!(:entity) { build_legal_entity }
  let!(:banque_compte) { build_general_account(code: "550000", name: "Banque") }
  let!(:stripe_compte) { build_general_account(code: "551000", name: "Stripe") }
  let!(:transferts) { build_general_account(code: "580000", name: "Virements internes", klass: 5, nature: "asset") }
  let!(:banque) { build_cash_account(entity, banque_compte) }
  let!(:stripe) do
    CashAccount.create!(name: "Stripe Claudy", kind: "stripe", legal_entity: entity,
                        general_account: stripe_compte, stripe_account_key: "claudy")
  end

  def versement(amount_cents: 126_900, arrival: Date.new(2026, 6, 15), stripe_id: "po_1")
    StripePayout.create!(account_key: "claudy", cash_account: stripe, stripe_id: stripe_id,
                         amount_cents: amount_cents, arrival_date: arrival)
  end

  def ligne(amount_cents: 126_900, entry_date: Date.new(2026, 6, 15), account: banque)
    build_cash_entry(account, amount_cents: amount_cents, entry_date: entry_date, label: "STRIPE PAYOUT")
  end

  it "propose le versement du montant exact arrivé le même jour" do
    po = versement
    matches = described_class.new.for_entry(ligne)

    expect(matches.map(&:payout)).to eq([po])
    expect(matches.first.confidence).to eq(90)
    expect(matches.first.reason).to include("exactement ce montant")
  end

  # Le versement arrive sur le compte un ou deux jours après sa date Stripe :
  # exiger le même jour raterait la majorité des cas.
  it "tolère trois jours d'écart entre la date du versement et celle de la ligne" do
    versement(arrival: Date.new(2026, 6, 12))

    expect(described_class.new.for_entry(ligne(entry_date: Date.new(2026, 6, 15)))).not_to be_empty
    expect(described_class.new.for_entry(ligne(entry_date: Date.new(2026, 6, 16)))).to be_empty
  end

  it "ne propose rien sur un montant différent" do
    versement(amount_cents: 126_900)

    expect(described_class.new.for_entry(ligne(amount_cents: 126_800))).to be_empty
  end

  it "ignore une ligne SORTANTE : un versement arrive, il ne part pas" do
    versement

    expect(described_class.new.for_entry(ligne(amount_cents: -126_900))).to be_empty
  end

  # Le versement se rapproche d'une ligne BANCAIRE, pas d'une ligne du compte
  # Stripe lui-même — sinon on rapprocherait le virement avec lui-même.
  it "ne propose rien sur une ligne du compte Stripe" do
    versement

    expect(described_class.new.for_entry(ligne(account: stripe))).to be_empty
  end

  it "ignore une ligne déjà affectée" do
    versement
    entry = ligne
    entry.cash_allocations.create!(general_account: transferts, legal_entity: entity, amount_cents: 126_900)

    expect(described_class.new.for_entry(entry.reload)).to be_empty
  end

  # Le proposer une seconde fois, c'est inviter à l'affecter deux fois.
  it "ne propose plus un versement déjà rapproché" do
    po = versement
    autre = ligne(entry_date: Date.new(2026, 6, 14))
    autre.cash_allocations.create!(general_account: transferts, legal_entity: entity,
                                   document: po, amount_cents: 126_900)

    expect(described_class.new.for_entry(ligne)).to be_empty
  end

  it "n'écrit AUCUNE allocation" do
    versement

    expect { described_class.new.for_entry(ligne) }.not_to change(CashAllocation, :count)
  end
end
