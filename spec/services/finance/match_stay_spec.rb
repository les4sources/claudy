require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# La cascade va du plus certain au plus faible, et deux candidats à égalité ne
# proposent RIEN. Deviner ici produit une erreur qu'on ne verra jamais : le
# montant est juste, seul le client est faux.
RSpec.describe Finance::MatchStay do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let(:cash_account) { build_cash_account(entity, bank_account) }
  let(:customer) { Customer.create!(first_name: "Jeanne", last_name: "Dupont", email: "jeanne@example.test") }
  let!(:stay) do
    Stay.create!(customer: customer, arrival_date: Date.new(2026, 8, 12), departure_date: Date.new(2026, 8, 15),
                 total_amount_cents: 130_000, payment_status: "pending")
  end

  def entry_with(**attributes)
    entry = build_cash_entry(cash_account, amount_cents: 130_000, entry_date: Date.new(2026, 8, 20))
    entry.update!(**attributes)
    entry
  end

  it "reconnaît le séjour nommé par sa référence" do
    match = described_class.new(cash_entry: entry_with(communication: "PAIEMENT SEJOUR ##{stay.id}")).run!

    expect(match.stay).to eq(stay)
    expect(match.confidence).to eq(95)
  end

  # Le faux positif constaté sur les vraies données : une communication
  # parfaitement banale se lisait comme une référence de séjour.
  it "ne prend pas « SEJOUR 12 AU 15 AOUT » pour une référence de séjour" do
    match = described_class.new(cash_entry: entry_with(communication: "SEJOUR 12 AU 15 AOUT")).run!

    expect(match&.stay).not_to eq(Stay.find_by(id: 12))
  end

  it "reconnaît le séjour par un jeton présent dans la communication" do
    match = described_class.new(cash_entry: entry_with(communication: "REF #{stay.token}")).run!

    expect(match.stay).to eq(stay)
  end

  it "reconnaît un IBAN déjà appris pour ce client" do
    CustomerBankAccount.remember!(customer: customer, iban: "BE99111122223333")

    match = described_class.new(cash_entry: entry_with(counterparty_iban: "BE99 1111 2222 3333")).run!

    expect(match.stay).to eq(stay)
    expect(match.rationale).to include("connu")
  end

  it "reconnaît le nom du tiers" do
    match = described_class.new(cash_entry: entry_with(counterparty_name: "JEANNE DUPONT")).run!

    expect(match.stay).to eq(stay)
    expect(match.confidence).to eq(60)
  end

  it "retombe sur le montant exact quand rien d'autre ne parle" do
    match = described_class.new(cash_entry: entry_with(communication: "VIREMENT")).run!

    expect(match.stay).to eq(stay)
    expect(match.confidence).to eq(45)
  end

  it "ne propose RIEN quand deux séjours ouverts portent le même montant" do
    autre = Customer.create!(first_name: "Paul", last_name: "Martin", email: "paul@example.test")
    Stay.create!(customer: autre, arrival_date: Date.new(2026, 8, 12), departure_date: Date.new(2026, 8, 16),
                 total_amount_cents: 130_000, payment_status: "pending")

    match = described_class.new(cash_entry: entry_with(communication: "VIREMENT")).run!

    expect(match).to be_nil
  end

  it "ne propose rien quand la communication nomme DEUX séjours" do
    autre = Stay.create!(customer: customer, arrival_date: Date.new(2026, 9, 1),
                         departure_date: Date.new(2026, 9, 3), total_amount_cents: 20_000,
                         payment_status: "pending")

    match = described_class.new(cash_entry: entry_with(communication: "SEJOUR ##{stay.id} ET SEJOUR ##{autre.id}")).run!

    expect(match).to be_nil
  end

  it "ne rattache pas un virement à un séjour déjà soldé, même nommé" do
    stay.update!(payment_status: "paid")

    match = described_class.new(cash_entry: entry_with(communication: "SEJOUR ##{stay.id}")).run!

    expect(match).to be_nil
  end

  # Un compte joint, ou une association et son trésorier : l'IBAN ne désigne
  # alors personne, et choisir serait attribuer la recette au mauvais client.
  it "ne propose rien quand un IBAN est connu pour deux clients" do
    autre = Customer.create!(first_name: "Paul", last_name: "Martin", email: "paul@example.test")
    Stay.create!(customer: autre, arrival_date: Date.new(2026, 8, 10), departure_date: Date.new(2026, 8, 11),
                 total_amount_cents: 9_999, payment_status: "pending")
    CustomerBankAccount.remember!(customer: customer, iban: "BE99111122223333")
    CustomerBankAccount.remember!(customer: autre, iban: "BE99111122223333")

    match = described_class.new(cash_entry: entry_with(counterparty_iban: "BE99111122223333",
                                                       counterparty_name: "")).run!

    # L'ambiguïté fait abstenir COMPLÈTEMENT : retomber sur le montant exact
    # après un IBAN partagé reviendrait à ignorer l'avertissement reçu.
    expect(match).to be_nil
  end

  # Un séjour à moitié payé ne doit pas se voir proposer un virement du montant
  # complet : c'est le solde restant qui compte.
  it "compare au solde restant, pas au total facturé" do
    Payment.create!(stay_id: stay.id, amount_cents: 30_000, status: "paid", payment_method: "transfer")

    complet = described_class.new(cash_entry: entry_with(communication: "VIREMENT")).run!
    expect(complet).to be_nil

    entry = build_cash_entry(cash_account, amount_cents: 100_000, entry_date: Date.new(2026, 8, 20))
    entry.update!(communication: "VIREMENT")
    expect(described_class.new(cash_entry: entry).run!&.stay).to eq(stay)
  end

  it "ignore un décaissement — un séjour ne se paie pas en sortant de l'argent" do
    entry = build_cash_entry(cash_account, amount_cents: -130_000, entry_date: Date.new(2026, 8, 20))

    expect(described_class.new(cash_entry: entry).run!).to be_nil
  end
end
