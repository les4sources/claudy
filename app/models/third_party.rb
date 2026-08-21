# Un tiers : celui à qui on doit, ou qui nous doit.
#
# Winbooks tenait ses tiers comme des comptes généraux auxiliaires rattachés au
# 440000. On ne reprend pas ce choix : 269 tiers dans un plan comptable qui
# compte 211 comptes noieraient le plan et mélangeraient deux natures d'objets.
# Le tiers est donc une entité à part, référencée par la ligne d'écriture.
#
# Il est porté par la LIGNE et non par l'écriture, pour deux raisons : c'est la
# ligne 440000 qu'on lettrera un jour contre son paiement, et un relevé bancaire
# touche plusieurs tiers dans une même écriture.
#
# `customer` et `human` sont facultatifs et le restent : la reprise Winbooks
# crée les tiers depuis un code alphanumérique (`ANTARGAZ`, `MICHAELHUL`) sans
# savoir à qui il correspond dans Claudy. Le rattachement se fait plus tard,
# à la main, sans bloquer l'import.
# == Schema Information
#
# Table name: third_parties
#
#  id          :bigint           not null, primary key
#  active      :boolean          default(TRUE), not null
#  code        :string           not null
#  deleted_at  :datetime
#  kind        :string           not null
#  name        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  customer_id :bigint
#  human_id    :bigint
#
# Indexes
#
#  index_third_parties_on_code         (code) UNIQUE
#  index_third_parties_on_customer_id  (customer_id)
#  index_third_parties_on_deleted_at   (deleted_at)
#  index_third_parties_on_human_id     (human_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (human_id => humans.id)
#
class ThirdParty < ApplicationRecord
  KINDS = %w[supplier customer both].freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :customer, optional: true
  belongs_to :human, optional: true
  has_many :journal_lines, dependent: :restrict_with_error

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :ordered, -> { order(:name) }
  scope :actives, -> { where(active: true) }
  scope :suppliers, -> { where(kind: %w[supplier both]) }
  scope :customers, -> { where(kind: %w[customer both]) }

  def to_s = name
end
