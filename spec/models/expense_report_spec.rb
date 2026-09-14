require "rails_helper"
# == Schema Information
#
# Table name: expense_reports
#
#  id               :bigint           not null, primary key
#  deleted_at       :datetime
#  kind             :string           default("expenses"), not null
#  notes            :text
#  paid_notified_at :datetime
#  paid_on          :date
#  posted_at        :datetime
#  processed_on     :date
#  reference        :string
#  rejection_reason :text
#  sequence_number  :integer
#  status           :string           default("recorded"), not null
#  submitted_on     :date
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  created_by_id    :bigint
#  fiscal_year_id   :bigint
#  human_id         :bigint           not null
#  legal_entity_id  :bigint           not null
#
# Indexes
#
#  index_expense_reports_on_created_by_id    (created_by_id)
#  index_expense_reports_on_deleted_at       (deleted_at)
#  index_expense_reports_on_fiscal_year_id   (fiscal_year_id)
#  index_expense_reports_on_human_id         (human_id)
#  index_expense_reports_on_legal_entity_id  (legal_entity_id)
#  index_expense_reports_on_reference        (reference) UNIQUE
#  index_expense_reports_on_sequence         (fiscal_year_id,kind,sequence_number) UNIQUE
#  index_expense_reports_on_status           (status)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (fiscal_year_id => fiscal_years.id)
#  fk_rails_...  (human_id => humans.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#
require Rails.root.join("spec/support/finance_builders")

# Epic #241, phase 1 — le modèle des notes de frais. Ce qui compte ici, c'est ce
# qui se fige et quand : tant que la note est enregistrée, tout se corrige ;
# passée en traitement, elle porte une pièce comptable et ne se réécrit plus.
RSpec.describe ExpenseReport, type: :model do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let(:human) { Human.create!(name: "Sébastien Test") }
  let(:account) { build_general_account(code: "610000", name: "Services et biens divers", klass: 6, nature: "expense") }

  def build_report(status: "recorded", kind: "expenses")
    ExpenseReport.create!(kind: kind, human: human, legal_entity: entity, status: status,
                          submitted_on: Date.new(2026, 6, 1))
  end

  def add_line(report, amount_cents: 2_490, spent_on: Date.new(2026, 5, 30), label: "Visserie")
    report.expense_lines.create!(spent_on: spent_on, label: label, amount_cents: amount_cents,
                                 general_account: account)
  end

  describe "#total_cents" do
    it "est la somme des lignes, jamais une colonne qui pourrait la contredire" do
      report = build_report
      add_line(report, amount_cents: 2_490)
      add_line(report, amount_cents: 1_010, label: "Terreau")

      expect(report.reload.total_cents).to eq(3_500)
      expect(report.total_money).to eq(Money.new(3_500, "EUR"))
    end

    it "vaut zéro sans ligne" do
      expect(build_report.total_cents).to eq(0)
    end
  end

  describe "les lignes" do
    it "refuse une ligne sans compte de charge" do
      report = build_report
      line = report.expense_lines.build(spent_on: Date.current, label: "Sans compte", amount_cents: 100)

      expect(line).not_to be_valid
      expect(line.errors[:general_account].join).to include("obligatoire")
    end

    it "refuse un montant nul ou négatif" do
      report = build_report
      line = report.expense_lines.build(spent_on: Date.current, label: "Zéro",
                                        amount_cents: 0, general_account: account)

      expect(line).not_to be_valid
    end

    it "lit un montant tapé avec une virgule" do
      line = ExpenseLine.new(amount_in_euros: "24,90")

      expect(line.amount_cents).to eq(2_490)
      expect(line.amount_in_euros).to eq("24,90")
    end
  end

  describe "l'immuabilité une fois en traitement" do
    it "refuse de changer le bénéficiaire d'une note en traitement" do
      report = build_report
      add_line(report)
      report.update!(status: "processing")

      autre = Human.create!(name: "Quelqu'un d'autre")
      expect(report.reload.update(human: autre)).to be(false)
      expect(report.errors[:base].join).to include("pièce comptable")
    end

    it "laisse avancer le statut et les dates de règlement" do
      report = build_report
      add_line(report)
      report.update!(status: "processing")

      expect(report.reload.update(status: "paid", paid_on: Date.current)).to be(true)
    end

    it "refuse d'ajouter une ligne à une note en traitement" do
      report = build_report
      add_line(report)
      report.update!(status: "processing")

      line = report.reload.expense_lines.build(spent_on: Date.current, label: "Ajout tardif",
                                               amount_cents: 500, general_account: account)
      expect(line).not_to be_valid
      expect(line.errors[:base].join).to include("plus modifiable")
    end

    it "refuse de retirer une ligne d'une note en traitement" do
      report = build_report
      line = add_line(report)
      report.update!(status: "processing")

      expect(line.reload.destroy).to be(false)
      expect(ExpenseLine.where(id: line.id)).to exist
    end
  end

  describe "le rejet" do
    it "exige un motif" do
      report = build_report
      expect(report.update(status: "rejected")).to be(false)
      expect(report.errors[:rejection_reason].join).to include("obligatoire")
    end
  end

  describe ".next_sequence_number" do
    it "compte par exercice ET par type" do
      year = build_fiscal_year(entity)
      frais = build_report
      frais.update!(fiscal_year: year, sequence_number: 7)

      expect(described_class.next_sequence_number(fiscal_year_id: year.id, kind: "expenses")).to eq(8)
      expect(described_class.next_sequence_number(fiscal_year_id: year.id, kind: "mileage")).to eq(1)
    end

    it "ne réattribue pas le numéro d'une note supprimée" do
      year = build_fiscal_year(entity)
      report = build_report
      report.update!(fiscal_year: year, sequence_number: 3)
      report.soft_delete!

      expect(described_class.next_sequence_number(fiscal_year_id: year.id, kind: "expenses")).to eq(4)
    end
  end

  describe ".format_reference" do
    it "produit NF-2026-014 et NM-2026-003" do
      expect(described_class.format_reference(prefix: "NF", year: 2026, number: 14)).to eq("NF-2026-014")
      expect(described_class.format_reference(prefix: "NM", year: 2026, number: 3)).to eq("NM-2026-003")
    end
  end
end
