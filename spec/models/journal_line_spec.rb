require "rails_helper"
# == Schema Information
#
# Table name: journal_lines
#
#  id                  :bigint           not null, primary key
#  credit_cents        :bigint           default(0), not null
#  debit_cents         :bigint           default(0), not null
#  deleted_at          :datetime
#  label               :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  analytic_account_id :bigint
#  general_account_id  :bigint           not null
#  journal_entry_id    :bigint           not null
#  team_id             :bigint
#  third_party_id      :bigint
#
# Indexes
#
#  index_journal_lines_on_analytic_account_id  (analytic_account_id)
#  index_journal_lines_on_deleted_at           (deleted_at)
#  index_journal_lines_on_general_account_id   (general_account_id)
#  index_journal_lines_on_journal_entry_id     (journal_entry_id)
#  index_journal_lines_on_team_id              (team_id)
#  index_journal_lines_on_third_party_id       (third_party_id)
#
# Foreign Keys
#
#  fk_rails_...  (analytic_account_id => analytic_accounts.id)
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (journal_entry_id => journal_entries.id)
#  fk_rails_...  (team_id => teams.id)
#  fk_rails_...  (third_party_id => third_parties.id)
#
require Rails.root.join("spec/support/finance_builders")

# Une ligne porte un sens et un seul. Une ligne à double sens rendrait la
# balance ininterprétable, et cette erreur-là arrive par script, pas par écran.
RSpec.describe JournalLine do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank) { build_general_account(code: "550000", name: "Banque") }
  let(:revenue) { build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue") }
  let(:entry) { post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue) }

  it "refuse une ligne qui porte un débit ET un crédit" do
    line = described_class.new(journal_entry: entry, general_account: bank,
                               debit_cents: 100, credit_cents: 100)

    expect(line).not_to be_valid
  end

  it "refuse une ligne sans montant" do
    line = described_class.new(journal_entry: entry, general_account: bank,
                               debit_cents: 0, credit_cents: 0)

    expect(line).not_to be_valid
  end

  # L'équilibre se valide sur l'écriture entière : toucher une ligne seule le
  # contournerait, et c'est le chemin qu'emprunte un script.
  it "refuse une modification de ligne qui déséquilibrerait son écriture" do
    line = entry.journal_lines.find { |l| l.debit_cents.positive? }

    expect(line.update(debit_cents: 999)).to be(false)
    expect(line.errors.full_messages.join).to match(/déséquilibrerait/i)
  end

  it "refuse la suppression d'une ligne seule" do
    line = entry.journal_lines.first

    expect(line.destroy).to be(false)
    expect(described_class.find_by(id: line.id)).to be_present
  end

  it "refuse de toucher une ligne d'écriture verrouillée" do
    entry.update_column(:locked_at, Time.current)
    line = entry.reload.journal_lines.first

    expect(line.update(label: "Retouché")).to be(false)
    expect(line.errors.full_messages.join).to match(/verrouillée/i)
  end

  it "donne un solde signé lisible du point de vue du compte" do
    debit = entry.journal_lines.find { |l| l.debit_cents.positive? }
    credit = entry.journal_lines.find { |l| l.credit_cents.positive? }

    expect(debit.signed_cents).to eq(10_000)
    expect(credit.signed_cents).to eq(-10_000)
  end
end
