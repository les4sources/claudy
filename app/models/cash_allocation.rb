# L'affectation d'une partie d'une ligne de trésorerie : à quel compte, pour
# quel pôle, pour quelle entité.
#
# L'entité juridique est portée ICI et pas sur le compte bancaire. Une facture
# de travaux de la Société simple payée depuis le compte de la Fondation est un
# mouvement Fondation et une charge Société simple : mettre l'entité sur le
# compte obligerait à mentir sur l'une des deux.
#
# Le pôle et l'axe analytique sont facultatifs et SANS valeur par défaut. Une
# allocation sans pôle reste visible comme non ventilée, ce qui est infiniment
# préférable à une allocation rangée d'office dans le mauvais pôle — le défaut
# de Winbooks, et la raison pour laquelle une recette d'hébergement se
# retrouvait dans le bar.
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
#
# Foreign Keys
#
#  fk_rails_...  (analytic_account_id => analytic_accounts.id)
#  fk_rails_...  (cash_entry_id => cash_entries.id)
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (team_id => teams.id)
#
class CashAllocation < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :cash_entry
  belongs_to :general_account
  belongs_to :analytic_account, optional: true
  belongs_to :team, optional: true
  belongs_to :legal_entity
  belongs_to :document, polymorphic: true, optional: true

  monetize :amount_cents

  validates :amount_cents, numericality: { only_integer: true, other_than: 0 }
  validate :same_direction_as_entry
  validate :within_entry_amount
  validate :entry_not_posted
  validate :entry_open

  before_destroy :refuse_when_posted

  scope :ordered, -> { order(:id) }

  private

  # Une allocation de sens contraire transformerait un encaissement en
  # décaissement partiel : ce n'est pas une affectation, c'est une autre ligne.
  def same_direction_as_entry
    return if cash_entry.blank? || amount_cents.to_i.zero?
    return if amount_cents.to_i.positive? == cash_entry.amount_cents.positive?

    errors.add(:amount_cents, "va dans le sens contraire du mouvement")
  end

  # La somme des allocations ne dépasse jamais le montant de la ligne. Sans ce
  # garde-fou, une erreur de saisie crée de l'argent qui n'a jamais existé.
  def within_entry_amount
    return if cash_entry.blank? || amount_cents.to_i.zero?

    autres = cash_entry.cash_allocations.where.not(id: id).sum(:amount_cents)
    total = autres + amount_cents.to_i
    return if total.abs <= cash_entry.amount_cents.abs

    reste = cash_entry.amount_cents - autres
    errors.add(:base, "Il ne reste que #{Money.new(reste, 'EUR').format} à affecter sur cette ligne")
  end

  # Réaffecter une ligne déjà comptabilisée ferait diverger l'écriture de ses
  # allocations. On annule d'abord la passation — ce qui la contre-passe — puis
  # on réaffecte. Vaut à la création COMME à la modification : sans ça, une
  # allocation existante resterait modifiable après passation et le grand livre
  # garderait une ventilation que plus personne ne voit à l'écran.
  def entry_not_posted
    return if cash_entry.blank? || !cash_entry.posted?

    errors.add(:base, "Cette ligne est déjà comptabilisée — annule sa passation avant de la réaffecter")
  end

  # Une ligne exclue est sortie du circuit : elle n'a pas à recevoir
  # d'affectation, sinon elle pourrait être comptabilisée par la bande.
  def entry_open
    return if cash_entry.blank? || cash_entry.status != "excluded"

    errors.add(:base, "Cette ligne est exclue — elle n'attend plus d'affectation")
  end

  def refuse_when_posted
    return if cash_entry.blank? || !cash_entry.posted?
    return if cash_entry.destroyed? || cash_entry.marked_for_destruction?

    errors.add(:base, "Cette ligne est déjà comptabilisée — annule sa passation d'abord")
    throw :abort
  end
end
