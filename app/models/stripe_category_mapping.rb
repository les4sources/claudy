# Où va une catégorie de ventes Stripe (epic #250, décision 4).
#
# En mode `ledger`, l'affectation se décide UNE FOIS par catégorie, jamais
# transaction par transaction : Tranches de Vie encaisse du pain, des légumes,
# des paniers — toujours les mêmes catégories, posées en métadonnée à l'émission
# du paiement (`source.metadata["categorie"]`).
#
# Ce qui n'est PAS ici : les frais (`618000`) et les versements (`580000`), fixés
# dans le code. Ce ne sont pas des décisions de gestion, ce sont des faits
# comptables.
#
# Et ce qui n'y est pas non plus : un défaut caché. Une catégorie sans
# correspondance laisse sa ligne en attente sur « À affecter » — visible, jamais
# rangée d'office (invariant B4). L'humain décide la correspondance,
# l'application l'applique.
# == Schema Information
#
# Table name: stripe_category_mappings
#
#  id                 :bigint           not null, primary key
#  account_key        :string           not null
#  category           :string
#  deleted_at         :datetime
#  notes              :text
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  general_account_id :bigint           not null
#  legal_entity_id    :bigint
#  team_id            :bigint
#
# Indexes
#
#  index_stripe_category_mappings_on_account_and_category      (account_key,category) UNIQUE WHERE ((category IS NOT NULL) AND (deleted_at IS NULL))
#  index_stripe_category_mappings_on_account_without_category  (account_key) UNIQUE WHERE ((category IS NULL) AND (deleted_at IS NULL))
#  index_stripe_category_mappings_on_deleted_at                (deleted_at)
#  index_stripe_category_mappings_on_general_account_id        (general_account_id)
#  index_stripe_category_mappings_on_legal_entity_id           (legal_entity_id)
#  index_stripe_category_mappings_on_team_id                   (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (team_id => teams.id)
#
class StripeCategoryMapping < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :general_account
  belongs_to :team, optional: true
  belongs_to :legal_entity, optional: true

  before_validation :normalize_category

  validates :account_key, presence: true
  validates :category, uniqueness: { scope: :account_key, allow_nil: true,
                                     message: "a déjà une correspondance sur ce compte" }
  validate :single_mapping_without_category, if: -> { category.nil? }

  scope :ordered, -> { order(Arel.sql("category NULLS FIRST")) }
  scope :for_account, ->(key) { where(account_key: key.to_s) }

  # « Sans catégorie » est une catégorie : elle a son libellé, sa correspondance
  # et sa ligne dans les écrans.
  NO_CATEGORY_LABEL = "Sans catégorie".freeze

  def category_label = category.presence || NO_CATEGORY_LABEL

  # La correspondance d'une transaction. `nil` en entrée cherche bien la
  # correspondance « sans catégorie » — et pas la première venue.
  def self.for(account_key, category)
    normalized = category.to_s.strip.presence
    for_account(account_key).find_by(category: normalized)
  end

  # Les attributs d'allocation qu'une correspondance dicte. Copiés sur la ligne,
  # jamais référencés : réaffecter une catégorie l'an prochain ne doit pas
  # réécrire les lignes de cette année (même règle que `CashMotif`).
  def allocation_attributes(fallback_entity: nil)
    {
      general_account: general_account,
      team: team,
      legal_entity: legal_entity || fallback_entity
    }
  end

  private

  def normalize_category
    self.category = category.to_s.strip.presence
  end

  def single_mapping_without_category
    scope = self.class.for_account(account_key).where(category: nil)
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:base, "Ce compte a déjà une correspondance « sans catégorie ».")
  end
end
