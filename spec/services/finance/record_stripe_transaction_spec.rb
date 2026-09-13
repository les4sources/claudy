require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Epic #250, phase 1 — une transaction du solde Stripe devient une ou deux
# lignes de trésorerie. Deux lignes plutôt qu'une nette : sans elles, la
# commission disparaît dans la recette et on ne sait plus ce que coûte le fait
# d'être payé par carte.
RSpec.describe Finance::RecordStripeTransaction do
  include FinanceBuilders

  let(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: 2026) }
  let!(:stripe_general) { build_general_account(code: "551000", name: "Stripe") }
  let!(:fee_account) { build_general_account(code: "618000", name: "Frais bancaires", klass: 6, nature: "expense") }
  let!(:transfer_account) do
    build_general_account(code: GeneralAccount::INTERNAL_TRANSFER_CODE, name: "Virements internes")
  end
  let!(:revenue_account) { build_general_account(code: "700100", name: "Ventes épicerie", klass: 7, nature: "revenue") }
  let(:team) { Team.create!(name: "Pôle Épicerie") }

  let!(:cash_account) do
    CashAccount.create!(name: "Stripe Tranches de Vie", kind: "stripe", legal_entity: entity,
                        general_account: stripe_general, stripe_account_key: "tranche_de_vie",
                        stripe_mode: "ledger")
  end

  def build_transaction(kind: "charge", gross: 1_000, fee: 29, net: nil, category: "pain",
                        stripe_id: "txn_001", payout: nil)
    StripeBalanceTransaction.create!(
      cash_account: cash_account, account_key: "tranche_de_vie", stripe_payout: payout,
      stripe_id: stripe_id, kind: kind, gross_cents: gross, fee_cents: fee,
      net_cents: net || (gross - fee), category: category, description: "Vente",
      occurred_at: Time.zone.local(2026, 6, 15), available_on: Date.new(2026, 6, 17)
    )
  end

  def record(transaction) = described_class.new(transaction: transaction).run!

  def entry_for(transaction, suffix)
    CashEntry.find_by(external_ref: "stripe:#{transaction.stripe_id}:#{suffix}")
  end

  describe "un encaissement" do
    it "crée deux lignes : la recette brute et la commission en négatif" do
      transaction = build_transaction

      expect { record(transaction) }.to change { CashEntry.count }.by(2)

      expect(entry_for(transaction, "gross").amount_cents).to eq(1_000)
      expect(entry_for(transaction, "fee").amount_cents).to eq(-29)
      expect(entry_for(transaction, "gross").cash_account).to eq(cash_account)
      expect(entry_for(transaction, "gross").source).to eq(transaction)
      expect(entry_for(transaction, "gross").entry_date).to eq(Date.new(2026, 6, 15))
      expect(entry_for(transaction, "gross").value_date).to eq(Date.new(2026, 6, 17))
    end

    it "affecte la recette d'après la correspondance de sa catégorie, et la comptabilise" do
      StripeCategoryMapping.create!(account_key: "tranche_de_vie", category: "pain",
                                    general_account: revenue_account, team: team)
      transaction = build_transaction
      record(transaction)

      recette = entry_for(transaction, "gross")
      expect(recette.status).to eq("allocated")
      expect(recette).to be_posted
      allocation = recette.cash_allocations.sole
      expect(allocation.general_account).to eq(revenue_account)
      expect(allocation.team).to eq(team)
      expect(allocation.legal_entity).to eq(entity)
    end

    # Invariant B4 : aucun défaut caché. Une catégorie que personne n'a décidée
    # laisse sa recette visible dans la file, elle ne se range pas toute seule.
    it "laisse la recette en attente quand la catégorie n'a pas de correspondance" do
      transaction = build_transaction
      record(transaction)

      expect(entry_for(transaction, "gross").status).to eq("pending")
      expect(entry_for(transaction, "gross").cash_allocations).to be_empty
    end

    # La commission, elle, n'attend personne : 618000 est un fait comptable, pas
    # une décision de gestion.
    it "affecte toujours la commission sur 618000" do
      transaction = build_transaction
      record(transaction)

      frais = entry_for(transaction, "fee")
      expect(frais.cash_allocations.sole.general_account).to eq(fee_account)
      expect(frais).to be_posted
    end

    it "ne crée pas de ligne de commission quand il n'y en a pas" do
      transaction = build_transaction(fee: 0, net: 1_000)

      expect { record(transaction) }.to change { CashEntry.count }.by(1)
      expect(entry_for(transaction, "fee")).to be_nil
    end

    it "cherche la correspondance « sans catégorie » quand la transaction n'en porte pas" do
      StripeCategoryMapping.create!(account_key: "tranche_de_vie", category: nil,
                                    general_account: revenue_account)
      transaction = build_transaction(category: nil)
      record(transaction)

      expect(entry_for(transaction, "gross").cash_allocations.sole.general_account).to eq(revenue_account)
    end
  end

  it "porte un remboursement en recette négative" do
    transaction = build_transaction(kind: "refund", gross: -1_000, fee: -29, net: -971)
    record(transaction)

    expect(entry_for(transaction, "gross").amount_cents).to eq(-1_000)
    expect(entry_for(transaction, "fee").amount_cents).to eq(29)
  end

  it "porte un frais facturé à part en une seule ligne négative sur 618000" do
    transaction = build_transaction(kind: "stripe_fee", gross: -2_583, fee: 0, net: -2_583, category: nil)

    expect { record(transaction) }.to change { CashEntry.count }.by(1)
    ligne = entry_for(transaction, "net")
    expect(ligne.amount_cents).to eq(-2_583)
    expect(ligne.cash_allocations.sole.general_account).to eq(fee_account)
  end

  describe "un versement" do
    let(:payout) do
      StripePayout.create!(account_key: "tranche_de_vie", cash_account: cash_account,
                           stripe_id: "po_001", amount_cents: 124_317,
                           arrival_date: Date.new(2026, 6, 20), automatic: false)
    end

    it "sort du solde Stripe sur le compte de virements internes, avec le versement en document" do
      transaction = build_transaction(kind: "payout", gross: -124_317, fee: 0, net: -124_317,
                                      category: nil, payout: payout)
      record(transaction)

      ligne = entry_for(transaction, "net")
      expect(ligne.amount_cents).to eq(-124_317)
      allocation = ligne.cash_allocations.sole
      expect(allocation.general_account).to eq(transfer_account)
      expect(allocation.document).to eq(payout)
      expect(ligne).to be_posted
    end
  end

  # On ne sait pas : la ligne existe, elle attend, et quelqu'un décidera. Pas de
  # compte fourre-tout qui absorbe ce qu'on n'a pas compris.
  it "laisse une transaction inconnue en attente, sans allocation" do
    transaction = build_transaction(kind: "other", gross: 500, fee: 0, net: 500, category: nil)
    record(transaction)

    ligne = entry_for(transaction, "net")
    expect(ligne.status).to eq("pending")
    expect(ligne.cash_allocations).to be_empty
  end

  it "est idempotent : rejouer ne crée ni ligne ni écriture" do
    StripeCategoryMapping.create!(account_key: "tranche_de_vie", category: "pain",
                                  general_account: revenue_account)
    transaction = build_transaction
    record(transaction)

    expect { record(transaction.reload) }.to change { CashEntry.count }.by(0)
    expect { record(transaction.reload) }.to change { JournalEntry.count }.by(0)
  end
end
