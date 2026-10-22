require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Une ligne de banque ventilée sur un séjour lui donne son paiement (Michael,
# 2026-10-22), sans jamais doubler un paiement encodé à la main.
RSpec.describe Stays::SyncBankPayments do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let(:banque) { build_cash_account(entity, build_general_account(code: "550000", name: "Banque")) }
  let(:caisse) { build_cash_account(entity, build_general_account(code: "570000", name: "Caisse"), name: "Caisse", kind: "cash") }
  let(:hebergement) { build_general_account(code: "700000", name: "Hébergement", klass: 7, nature: "revenue") }
  let(:customer) { Customer.create!(first_name: "Jeanne", last_name: "Dupont", email: "jeanne@example.test") }
  let(:stay) do
    Stay.create!(customer: customer, arrival_date: Date.new(2026, 8, 12), departure_date: Date.new(2026, 8, 15))
        .tap { |s| s.update_column(:total_amount_cents, 100_000) }
  end

  def ventiler(ligne, montant = ligne.amount_cents)
    ligne.cash_allocations.create!(general_account: hebergement, amount_cents: montant, legal_entity: entity,
                                   document: stay, label: "Hébergement — séjour ##{stay.id}")
  end

  def a_la_main(montant, methode: "bank_transfer", statut: "paid")
    Payment.create!(stay: stay, amount_cents: montant, payment_method: methode, status: statut,
                    paid_on: Date.new(2026, 6, 10))
  end

  def sync = described_class.new(stay: stay.reload).tap(&:run!)

  it "crée un virement encaissé à la date de la ligne quand rien n'est encodé" do
    ligne = build_cash_entry(banque, amount_cents: 30_000)
    ventiler(ligne)

    expect(sync.outcomes).to eq(ligne.id => :kept) # déjà créé par l'affectation, au commit
    paiement = stay.direct_payments.sole
    expect(paiement).to have_attributes(amount_cents: 30_000, payment_method: "bank_transfer", status: "paid",
                                        paid_on: ligne.entry_date, cash_entry_id: ligne.id,
                                        created_from_cash_entry: true)
    expect(stay.reload.payment_status).to eq("partially_paid")
  end

  it "pose un paiement « Liquide » pour une ligne de caisse" do
    ventiler(build_cash_entry(caisse, amount_cents: 100_000))

    expect(stay.direct_payments.sole.payment_method).to eq("cash")
    expect(stay.reload.payment_status).to eq("paid")
  end

  it "relie le paiement encodé à la main du même montant au lieu d'en créer un second" do
    deja = a_la_main(30_000, statut: "pending")
    ligne = build_cash_entry(banque, amount_cents: 30_000)
    ventiler(ligne)

    expect(stay.direct_payments.count).to eq(1)
    expect(deja.reload).to have_attributes(cash_entry_id: ligne.id, created_from_cash_entry: false, status: "paid")
    expect(described_class.summary(stay: stay, cash_entry: ligne)).to include("déjà encodé")
  end

  it "ne crée rien quand un paiement à la main d'un autre montant attend encore sa ligne" do
    a_la_main(50_000)
    ligne = build_cash_entry(banque, amount_cents: 25_000)
    ventiler(ligne)

    expect(stay.direct_payments.count).to eq(1)
    expect(sync.outcomes).to eq(ligne.id => :unmatched)
    expect(described_class.summary(stay: stay, cash_entry: ligne)).to include("autre montant")
  end

  it "crée le solde quand l'acompte encodé à la main a déjà trouvé sa ligne" do
    acompte = a_la_main(30_000)
    premiere = build_cash_entry(banque, amount_cents: 30_000, entry_date: Date.new(2026, 6, 10))
    ventiler(premiere)
    solde = build_cash_entry(banque, amount_cents: 70_000, entry_date: Date.new(2026, 7, 1))
    ventiler(solde)

    expect(acompte.reload.cash_entry_id).to eq(premiere.id)
    expect(stay.direct_payments.find_by(cash_entry_id: solde.id)).to be_created_from_cash_entry
    expect(stay.reload.payment_status).to eq("paid")
  end

  it "ne crée rien sur un séjour déjà soldé autrement" do
    Payment.create!(stay: stay, amount_cents: 100_000, payment_method: "stripe", status: "paid",
                    stripe_payment_intent_id: "pi_123")
    ligne = build_cash_entry(banque, amount_cents: 20_000)
    ventiler(ligne)

    expect(stay.direct_payments.count).to eq(1)
    expect(sync.outcomes).to eq(ligne.id => :settled)
  end

  it "ignore les lignes d'un compte Stripe" do
    stripe = build_cash_account(entity, build_general_account(code: "580000", name: "Stripe"), name: "Stripe", kind: "stripe")
    ventiler(build_cash_entry(stripe, amount_cents: 30_000))

    expect(stay.direct_payments).to be_empty
  end

  it "suit le montant affecté et retire le paiement créé quand l'affectation part" do
    ligne = build_cash_entry(banque, amount_cents: 30_000)
    allocation = ventiler(ligne, 20_000)
    expect(stay.direct_payments.sole.amount_cents).to eq(20_000)

    allocation.update!(amount_cents: 30_000)
    expect(stay.direct_payments.sole.amount_cents).to eq(30_000)

    allocation.destroy!
    expect(stay.direct_payments).to be_empty
    expect(stay.reload.payment_status).to eq("pending")
  end

  it "détache sans le supprimer le paiement à la main quand l'affectation part" do
    deja = a_la_main(30_000)
    allocation = ventiler(build_cash_entry(banque, amount_cents: 30_000))

    allocation.destroy!

    expect(deja.reload).to have_attributes(cash_entry_id: nil, deleted_at: nil)
  end

  it "rend le paiement au premier séjour quand l'affectation change de séjour" do
    autre = Stay.create!(customer: customer, arrival_date: Date.new(2026, 9, 1), departure_date: Date.new(2026, 9, 3))
    autre.update_column(:total_amount_cents, 100_000)
    allocation = ventiler(build_cash_entry(banque, amount_cents: 30_000))

    allocation.update!(document: autre)

    expect(stay.direct_payments).to be_empty
    expect(autre.direct_payments.sole.amount_cents).to eq(30_000)
  end
end
