# Un motif de caisse (epic #243, décision 2) : le vocabulaire réel de la feuille
# de caisse — « Bar », « Dépôt en banque », « Facture payée en espèces » — avec
# l'affectation comptable qui va avec.
#
# LE MOTIF EST L'AFFECTATION. Il porte le compte général, le pôle et l'entité,
# si bien qu'une ligne de caisse se saisit en choisissant un motif et un
# montant, au lieu du formulaire générique suivi d'un second geste
# d'affectation. La phase 2 s'en sert pour la feuille mensuelle.
#
# Un motif se modifie (décision 4) : une ligne déjà saisie garde l'affectation
# qu'elle avait à ce moment-là, parce que l'allocation en est une COPIE et non
# une référence. Modifier un motif ne réécrit donc jamais le passé.
# == Schema Information
#
# Table name: cash_motifs
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  deleted_at         :datetime
#  direction          :string           default("both"), not null
#  label              :string           not null
#  position           :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  general_account_id :bigint           not null
#  legal_entity_id    :bigint           not null
#  team_id            :bigint
#
# Indexes
#
#  index_cash_motifs_on_deleted_at          (deleted_at)
#  index_cash_motifs_on_general_account_id  (general_account_id)
#  index_cash_motifs_on_legal_entity_id     (legal_entity_id)
#  index_cash_motifs_on_position_and_id     (position,id)
#  index_cash_motifs_on_team_id             (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (team_id => teams.id)
#
class CashMotif < ApplicationRecord
  DIRECTIONS = %w[in out both].freeze
  DIRECTION_LABELS = {
    "in"   => "Entrée",
    "out"  => "Sortie",
    "both" => "Les deux"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :general_account
  belongs_to :legal_entity
  belongs_to :team, optional: true

  validates :label, presence: true, uniqueness: true
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:position, :id) }
  scope :actives, -> { where(active: true) }
  # Les motifs proposables pour un sens donné : ceux de ce sens, plus ceux qui
  # valent dans les deux (« Divers », un jour).
  scope :for_direction, ->(direction) { where(direction: [direction.to_s, "both"]) }

  def direction_label = DIRECTION_LABELS.fetch(direction, direction)

  def incoming? = direction == "in"
  def outgoing? = direction == "out"

  # Le signe qu'un montant saisi doit prendre sur la ligne de caisse. `both`
  # n'en impose aucun : c'est la saisie qui tranchera (phase 2).
  def signed_cents(amount_cents)
    magnitude = amount_cents.to_i.abs
    return magnitude if incoming?
    return -magnitude if outgoing?

    amount_cents.to_i
  end

  # L'affectation à COPIER sur la ligne (décision 4) — jamais une référence.
  def allocation_attributes
    { general_account_id: general_account_id, team_id: team_id, legal_entity_id: legal_entity_id }
  end

  def self.next_position = (unscoped.maximum(:position) || 0) + 1
end
