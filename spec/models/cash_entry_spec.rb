require "rails_helper"
# == Schema Information
#
# Table name: cash_entries
#
#  id                :bigint           not null, primary key
#  allocated_at      :datetime
#  amount_cents      :bigint           not null
#  communication     :string
#  counterparty_iban :string
#  counterparty_name :string
#  deleted_at        :datetime
#  entry_date        :date             not null
#  excluded_reason   :string
#  external_ref      :string
#  fingerprint       :string
#  label             :string           not null
#  notes             :text
#  source_type       :string
#  statement_ref     :string
#  status            :string           default("pending"), not null
#  transaction_code  :string
#  value_date        :date
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  cash_account_id   :bigint           not null
#  cash_motif_id     :bigint
#  source_id         :bigint
#
# Indexes
#
#  index_cash_entries_on_cash_account_id   (cash_account_id)
#  index_cash_entries_on_cash_motif_id     (cash_motif_id)
#  index_cash_entries_on_deleted_at        (deleted_at)
#  index_cash_entries_on_entry_date        (entry_date)
#  index_cash_entries_on_external_ref      (cash_account_id,external_ref) UNIQUE WHERE (external_ref IS NOT NULL)
#  index_cash_entries_on_fingerprint       (cash_account_id,fingerprint) UNIQUE WHERE (fingerprint IS NOT NULL)
#  index_cash_entries_on_source            (source_type,source_id)
#  index_cash_entries_on_status            (status)
#  index_cash_entries_on_transaction_code  (transaction_code)
#
# Foreign Keys
#
#  fk_rails_...  (cash_account_id => cash_accounts.id)
#  fk_rails_...  (cash_motif_id => cash_motifs.id)
#
require Rails.root.join("spec/support/finance_builders")

# Une ligne de trésorerie est un FAIT : elle ne se supprime pas, elle s'exclut
# avec un motif. Supprimer effacerait la question au lieu d'y répondre.
RSpec.describe CashEntry do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let(:revenue) { build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue") }
  let(:cash_account) { build_cash_account(entity, bank_account) }
  let(:entry) { build_cash_entry(cash_account) }

  it "refuse d'être supprimée" do
    expect(entry.destroy).to be(false)
    expect(described_class.find_by(id: entry.id)).to be_present
  end

  it "s'exclut avec un motif" do
    entry.exclude!("Doublon d'import")

    expect(entry.reload.status).to eq("excluded")
    expect(entry.excluded_reason).to eq("Doublon d'import")
  end

  it "refuse l'exclusion sans motif" do
    entry.status = "excluded"

    expect(entry).not_to be_valid
  end

  it "refuse un montant nul — un mouvement de zéro n'est pas un mouvement" do
    expect(described_class.new(cash_account: cash_account, entry_date: Date.current,
                               amount_cents: 0, label: "Rien")).not_to be_valid
  end

  it "suit ce qui reste à affecter" do
    allocate(entry, account: revenue, amount_cents: 30_000, entity: entity)

    expect(entry.reload.remaining_cents).to eq(100_000)
    expect(entry).not_to be_fully_allocated

    allocate(entry, account: revenue, amount_cents: 100_000, entity: entity)
    expect(entry.reload).to be_fully_allocated
  end

  it "se fige une fois comptabilisée" do
    allocate(entry, account: revenue, amount_cents: 130_000, entity: entity)
    Accounting::PostCashEntry.new(cash_entry: entry).run!

    expect(entry.reload.update(amount_cents: 999)).to be(false)
    expect(entry.errors.full_messages.join).to match(/annule sa passation/i)
  end

  it "refuse d'être exclue tant qu'elle est comptabilisée" do
    allocate(entry, account: revenue, amount_cents: 130_000, entity: entity)
    Accounting::PostCashEntry.new(cash_entry: entry).run!

    expect { entry.reload.exclude!("Erreur") }.to raise_error(ArgumentError, /annule sa passation/i)
  end

  it "choisit son journal selon le support" do
    caisse = build_cash_account(entity, bank_account, name: "Caisse du bar", kind: "cash")

    expect(entry.journal).to eq("bank")
    expect(build_cash_entry(caisse).journal).to eq("cash")
  end
  # La recherche du journal : on cherche une ligne par ce qu'on en retient, et
  # ce qu'on retient n'est pas toujours dans la même colonne.
  describe ".matching" do
    let!(:epicerie) do
      CashEntry.create!(cash_account: cash_account, entry_date: Date.new(2026, 8, 17),
                        amount_cents: 20_089, label: "Vanhamme — Épicerie",
                        communication: "Épicerie", counterparty_name: "Vanhamme - de Tiege")
    end
    let!(:bar) do
      CashEntry.create!(cash_account: cash_account, entry_date: Date.new(2026, 8, 27),
                        amount_cents: 1_400, label: "Frennet — Bar",
                        communication: "Bar", counterparty_name: "Frennet - Deheneffe")
    end

    it "trouve par la communication, sans accents ni casse" do
      expect(CashEntry.matching("epicerie")).to contain_exactly(epicerie)
      expect(CashEntry.matching("ÉPICERIE")).to contain_exactly(epicerie)
    end

    it "trouve par la contrepartie" do
      expect(CashEntry.matching("frennet")).to contain_exactly(bar)
    end

    it "trouve par le libellé" do
      expect(CashEntry.matching("vanhamme")).to contain_exactly(epicerie)
    end

    it "ne rend rien quand rien ne correspond" do
      expect(CashEntry.matching("zzzintrouvable")).to be_empty
    end

    # Le terme vient d'un champ de formulaire : un `%` tapé par erreur ne doit
    # pas se transformer en joker qui rend tout le journal.
    it "échappe les jokers SQL" do
      expect(CashEntry.matching("%")).to be_empty
    end

    it "supporte une ligne sans communication ni contrepartie" do
      nue = CashEntry.create!(cash_account: cash_account, entry_date: Date.new(2026, 8, 1),
                              amount_cents: 500, label: "Régularisation caisse")
      expect(CashEntry.matching("regularisation")).to contain_exactly(nue)
    end
  end

end
