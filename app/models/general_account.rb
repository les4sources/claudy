# Un compte du plan comptable général.
#
# Le code reste COURT. Winbooks encodait `6011xx` où le suffixe désignait le
# pôle : le plan comptable se multipliait par le nombre de pôles, et réorganiser
# la gouvernance obligeait à réécrire des comptes. Ici le pôle vit sur sa propre
# colonne analytique et le compte général ne dit qu'une chose — la nature de ce
# qui est imputé.
# == Schema Information
#
# Table name: general_accounts
#
#  id           :bigint           not null, primary key
#  active       :boolean          default(TRUE), not null
#  code         :string           not null
#  deleted_at   :datetime
#  klass        :integer          not null
#  name         :string           not null
#  nature       :string           not null
#  reconcilable :boolean          default(FALSE), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_general_accounts_on_code        (code) UNIQUE
#  index_general_accounts_on_deleted_at  (deleted_at)
#  index_general_accounts_on_klass       (klass)
#
class GeneralAccount < ApplicationRecord
  NATURES = %w[asset liability equity revenue expense].freeze
  NATURE_LABELS = {
    "asset" => "Actif",
    "liability" => "Passif",
    "equity" => "Capitaux propres",
    "revenue" => "Produit",
    "expense" => "Charge"
  }.freeze

  # Le compte de transferts internes du PCMN. Son solde doit valoir zéro à tout
  # instant : un mouvement entre deux comptes de la maison ne crée pas de
  # richesse. `rake accounting:verify_internal_transfers` s'appuie dessus.
  INTERNAL_TRANSFER_CODE = "580000".freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  has_many :journal_lines, dependent: :restrict_with_error
  has_many :cash_accounts, dependent: :restrict_with_error

  validates :code, presence: true, uniqueness: true, format: { with: /\A\d{3,8}\z/, message: "doit être numérique" }
  validates :name, presence: true
  validates :klass, inclusion: { in: 1..7 }
  validates :nature, inclusion: { in: NATURES }

  scope :ordered, -> { order(:code) }
  scope :actives, -> { where(active: true) }
  scope :in_class, ->(klass) { where(klass: klass) }

  def nature_label = NATURE_LABELS.fetch(nature, nature)
  def to_s = "#{code} #{name}"

  # Un produit et un passif augmentent au crédit ; un actif et une charge
  # augmentent au débit. C'est ce qui donne au solde son signe lisible.
  def credit_natured? = %w[liability equity revenue].include?(nature)
end
