# Un relevé lu dans un fichier CODA.
#
# Sa raison d'être n'est pas l'archivage : c'est la MÉMOIRE DU CHAÎNAGE. En
# comparant l'ancien solde d'un relevé au dernier nouveau solde déjà importé
# pour le même compte, on détecte le relevé manquant — celui que l'export
# bancaire a sauté sans rien dire, et qui ferait un trou invisible dans le
# journal de trésorerie.
# == Schema Information
#
# Table name: coda_statements
#
#  id                :bigint           not null, primary key
#  deleted_at        :datetime
#  entries_count     :integer          default(0), not null
#  new_balance_cents :bigint           not null
#  new_balance_date  :date
#  old_balance_cents :bigint           not null
#  old_balance_date  :date
#  period_year       :integer          not null
#  sequence_number   :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  cash_account_id   :bigint           not null
#  coda_import_id    :bigint           not null
#
# Indexes
#
#  index_coda_statements_on_account_and_sequence  (cash_account_id,period_year,sequence_number) UNIQUE
#  index_coda_statements_on_cash_account_id       (cash_account_id)
#  index_coda_statements_on_coda_import_id        (coda_import_id)
#  index_coda_statements_on_deleted_at            (deleted_at)
#
# Foreign Keys
#
#  fk_rails_...  (cash_account_id => cash_accounts.id)
#  fk_rails_...  (coda_import_id => coda_imports.id)
#
class CodaStatement < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :coda_import
  belongs_to :cash_account

  validates :sequence_number, :period_year, presence: true
  validates :sequence_number, uniqueness: { scope: [:cash_account_id, :period_year] }

  scope :ordered, -> { order(:new_balance_date, :sequence_number) }

  def self.last_for(cash_account)
    where(cash_account_id: cash_account.id).order(:new_balance_date, :sequence_number).last
  end

  def label = "n°#{sequence_number}/#{period_year}"
end
