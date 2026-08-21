require "rails_helper"
# == Schema Information
#
# Table name: cash_allocations
#
#  id                  :bigint           not null, primary key
#  amount_cents        :bigint           not null
#  deleted_at          :datetime
#  document_type       :string
#  label               :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  analytic_account_id :bigint
#  cash_entry_id       :bigint           not null
#  document_id         :bigint
#  general_account_id  :bigint           not null
#  legal_entity_id     :bigint           not null
#  team_id             :bigint
#  third_party_id      :bigint
#
# Indexes
#
#  index_cash_allocations_on_analytic_account_id            (analytic_account_id)
#  index_cash_allocations_on_cash_entry_id                  (cash_entry_id)
#  index_cash_allocations_on_deleted_at                     (deleted_at)
#  index_cash_allocations_on_document_type_and_document_id  (document_type,document_id)
#  index_cash_allocations_on_general_account_id             (general_account_id)
#  index_cash_allocations_on_legal_entity_id                (legal_entity_id)
#  index_cash_allocations_on_team_id                        (team_id)
#  index_cash_allocations_on_third_party_id                 (third_party_id)
#
# Foreign Keys
#
#  fk_rails_...  (analytic_account_id => analytic_accounts.id)
#  fk_rails_...  (cash_entry_id => cash_entries.id)
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (team_id => teams.id)
#  fk_rails_...  (third_party_id => third_parties.id)
#
require Rails.root.join("spec/support/finance_builders")

# Les trois refus qui empêchent une affectation de créer de l'argent : pas plus
# que le montant, pas dans l'autre sens, pas après comptabilisation.
RSpec.describe CashAllocation do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let(:revenue) { build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue") }
  let(:cash_account) { build_cash_account(entity, bank_account) }
  let(:entry) { build_cash_entry(cash_account, amount_cents: 130_000) }

  it "refuse de dépasser le montant de la ligne" do
    allocation = entry.cash_allocations.new(general_account: revenue, legal_entity: entity,
                                            amount_cents: 200_000)

    expect(allocation).not_to be_valid
    expect(allocation.errors.full_messages.join).to match(/il ne reste/i)
  end

  it "refuse une allocation de sens contraire" do
    allocation = entry.cash_allocations.new(general_account: revenue, legal_entity: entity,
                                            amount_cents: -5_000)

    expect(allocation).not_to be_valid
    expect(allocation.errors.full_messages.join).to match(/sens contraire/i)
  end

  it "exige une entité juridique — c'est elle qui dit à qui la charge appartient" do
    allocation = entry.cash_allocations.new(general_account: revenue, amount_cents: 1_000)

    expect(allocation).not_to be_valid
  end

  it "accepte de découper une ligne en plusieurs affectations" do
    allocate(entry, account: revenue, amount_cents: 80_000, entity: entity)
    allocate(entry, account: revenue, amount_cents: 50_000, entity: entity)

    expect(entry.reload.remaining_cents).to eq(0)
  end

  it "refuse d'affecter une ligne exclue" do
    entry.exclude!("Doublon d'import")
    allocation = entry.cash_allocations.new(general_account: revenue, legal_entity: entity, amount_cents: 1_000)

    expect(allocation).not_to be_valid
    expect(allocation.errors.full_messages.join).to match(/exclue/i)
  end

  it "refuse de MODIFIER une allocation après comptabilisation, pas seulement d'en créer" do
    allocation = allocate(entry, account: revenue, amount_cents: 130_000, entity: entity)
    Accounting::PostCashEntry.new(cash_entry: entry).run!

    expect(allocation.reload.update(amount_cents: 10_000)).to be(false)
  end

  it "refuse d'affecter une ligne déjà comptabilisée" do
    allocate(entry, account: revenue, amount_cents: 130_000, entity: entity)
    Accounting::PostCashEntry.new(cash_entry: entry).run!

    allocation = entry.reload.cash_allocations.new(general_account: revenue, legal_entity: entity,
                                                   amount_cents: 100)
    expect(allocation).not_to be_valid
    expect(allocation.errors.full_messages.join).to match(/déjà comptabilisée/i)
  end
end
