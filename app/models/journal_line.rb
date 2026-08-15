# Une ligne d'écriture : un compte, un sens, un montant.
#
# Un sens ET UN SEUL. Une ligne qui porterait un débit et un crédit rendrait la
# balance ininterprétable ; la contrainte est posée en base autant que dans le
# modèle, parce que ce genre d'erreur arrive par script et pas par écran.
#
# L'analytique et le pôle sont OPTIONNELS et sans valeur par défaut : une ligne
# non affectée doit rester visible comme telle. Une affectation par défaut
# silencieuse est exactement ce qui a produit, chez Winbooks, des recettes
# d'hébergement rangées dans le bar.
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
#
# Indexes
#
#  index_journal_lines_on_analytic_account_id  (analytic_account_id)
#  index_journal_lines_on_deleted_at           (deleted_at)
#  index_journal_lines_on_general_account_id   (general_account_id)
#  index_journal_lines_on_journal_entry_id     (journal_entry_id)
#  index_journal_lines_on_team_id              (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (analytic_account_id => analytic_accounts.id)
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (journal_entry_id => journal_entries.id)
#  fk_rails_...  (team_id => teams.id)
#
class JournalLine < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :journal_entry
  belongs_to :general_account
  belongs_to :analytic_account, optional: true
  belongs_to :team, optional: true

  monetize :debit_cents
  monetize :credit_cents

  validates :debit_cents, :credit_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :exactly_one_side
  validate :entry_not_locked
  validate :entry_stays_balanced, on: :update

  before_destroy :refuse_destruction

  scope :debits, -> { where("debit_cents > 0") }
  scope :credits, -> { where("credit_cents > 0") }

  def amount_cents = debit_cents.positive? ? debit_cents : credit_cents
  def side = debit_cents.positive? ? "debit" : "credit"

  # Le solde signé d'une ligne, du point de vue du compte : débit positif,
  # crédit négatif. C'est la convention du grand livre.
  def signed_cents = debit_cents - credit_cents

  private

  def exactly_one_side
    both = debit_cents.to_i.positive? && credit_cents.to_i.positive?
    neither = debit_cents.to_i.zero? && credit_cents.to_i.zero?
    return unless both || neither

    errors.add(:base, "Une ligne porte un débit ou un crédit, jamais les deux ni aucun")
  end

  # L'équilibre se valide sur l'écriture entière, donc toucher une ligne SEULE
  # le contournerait — et c'est le chemin qu'emprunte un script, pas un écran.
  # Ces trois gardes ferment la porte par la ligne.
  def entry_not_locked
    return if journal_entry.blank? || !journal_entry.locked?
    return if new_record? && journal_entry.new_record?

    errors.add(:base, "L'écriture est verrouillée : contre-passe-la plutôt que d'en retoucher une ligne")
  end

  def entry_stays_balanced
    return if journal_entry.blank?

    autres = journal_entry.journal_lines.where.not(id: id)
    debits = autres.sum(:debit_cents) + debit_cents.to_i
    credits = autres.sum(:credit_cents) + credit_cents.to_i
    return if debits == credits

    errors.add(:base, "Cette modification déséquilibrerait l'écriture : #{debits} au débit, #{credits} au crédit")
  end

  def refuse_destruction
    return if journal_entry.blank? || journal_entry.destroyed? || journal_entry.marked_for_destruction?
    return unless journal_entry.persisted?

    errors.add(:base, "Une ligne ne se supprime pas seule — elle déséquilibrerait son écriture")
    throw :abort
  end
end
