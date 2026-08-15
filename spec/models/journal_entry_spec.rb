require "rails_helper"
# == Schema Information
#
# Table name: journal_entries
#
#  id              :bigint           not null, primary key
#  deleted_at      :datetime
#  entry_date      :date             not null
#  journal         :string           not null
#  label           :string           not null
#  locked_at       :datetime
#  number          :integer          not null
#  posted_at       :datetime         not null
#  source_type     :string
#  whodunnit       :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  fiscal_year_id  :bigint           not null
#  legal_entity_id :bigint           not null
#  reversal_of_id  :bigint
#  source_id       :bigint
#
# Indexes
#
#  index_journal_entries_on_deleted_at       (deleted_at)
#  index_journal_entries_on_entry_date       (entry_date)
#  index_journal_entries_on_fiscal_year_id   (fiscal_year_id)
#  index_journal_entries_on_legal_entity_id  (legal_entity_id)
#  index_journal_entries_on_sequence         (fiscal_year_id,journal,number) UNIQUE
#  index_journal_entries_on_single_reversal  (reversal_of_id) UNIQUE WHERE (reversal_of_id IS NOT NULL)
#  index_journal_entries_on_source           (source_type,source_id,journal) UNIQUE WHERE (source_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (fiscal_year_id => fiscal_years.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (reversal_of_id => journal_entries.id)
#
require Rails.root.join("spec/support/finance_builders")

# L'invariant qui justifie tout le lot B : la somme des débits égale la somme
# des crédits. S'il ne tient pas au modèle, il ne tient nulle part — un import,
# un rake ou la console finiraient toujours par passer à côté d'un écran.
RSpec.describe JournalEntry do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank) { build_general_account(code: "550000", name: "Banque") }
  let(:revenue) { build_general_account(code: "700000", name: "Locations", klass: 7, nature: "revenue") }

  def new_entry(lines, entry_date: Date.new(2026, 6, 15))
    entry = described_class.new(fiscal_year: fiscal_year, legal_entity: entity, journal: "misc",
                                number: 1, entry_date: entry_date, label: "Test", posted_at: Time.current)
    lines.each { |attrs| entry.journal_lines.build(attrs) }
    entry
  end

  it "refuse une écriture déséquilibrée" do
    entry = new_entry([
                        { general_account: bank, debit_cents: 10_000 },
                        { general_account: revenue, credit_cents: 9_000 }
                      ])

    expect(entry).not_to be_valid
    expect(entry.errors.full_messages.join).to match(/déséquilibrée/i)
  end

  it "accepte une écriture équilibrée sur plusieurs lignes" do
    entry = new_entry([
                        { general_account: bank, debit_cents: 10_000 },
                        { general_account: revenue, credit_cents: 6_000 },
                        { general_account: revenue, credit_cents: 4_000 }
                      ])

    expect(entry).to be_valid
  end

  it "refuse une écriture à une seule ligne" do
    entry = new_entry([{ general_account: bank, debit_cents: 0, credit_cents: 0 }])

    expect(entry).not_to be_valid
    expect(entry.errors.full_messages.join).to match(/au moins deux lignes/i)
  end

  it "refuse une écriture dont l'entité n'est pas celle de son exercice" do
    autre = build_legal_entity(name: "SRL de test", form: "srl")
    entry = new_entry([
                        { general_account: bank, debit_cents: 100 },
                        { general_account: revenue, credit_cents: 100 }
                      ])
    entry.legal_entity = autre

    expect(entry).not_to be_valid
    expect(entry.errors.full_messages.join).to match(/exercice/i)
  end

  it "refuse une date hors de son exercice" do
    entry = new_entry([
                        { general_account: bank, debit_cents: 100 },
                        { general_account: revenue, credit_cents: 100 }
                      ], entry_date: Date.new(2025, 6, 15))

    expect(entry).not_to be_valid
    expect(entry.errors.full_messages.join).to match(/hors de l'exercice/i)
  end

  it "refuse d'écrire dans un exercice clôturé" do
    fiscal_year.close!
    entry = new_entry([
                        { general_account: bank, debit_cents: 100 },
                        { general_account: revenue, credit_cents: 100 }
                      ])

    expect(entry).not_to be_valid
    expect(entry.errors.full_messages.join).to match(/clôturé/i)
  end

  # Une écriture verrouillée ne se corrige pas : elle se contre-passe. Sinon la
  # numérotation garde des trous et le passé devient négociable.
  it "refuse la modification et la suppression d'une écriture verrouillée" do
    entry = post_simple_entry(entity: entity, debit_account: bank, credit_account: revenue)
    entry.update_column(:locked_at, Time.current)
    entry.reload

    expect(entry.update(label: "Retouché")).to be(false)
    expect(entry.destroy).to be(false)
    expect(described_class.find_by(id: entry.id)).to be_present
  end
end
