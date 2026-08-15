# Un relevé lu dans un fichier CODA.
#
# Sa raison d'être n'est pas l'archivage : c'est la MÉMOIRE DU CHAÎNAGE. En
# comparant l'ancien solde d'un relevé au dernier nouveau solde déjà importé
# pour le même compte, on détecte le relevé manquant — celui que l'export
# bancaire a sauté sans rien dire, et qui ferait un trou invisible dans le
# journal de trésorerie.
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
