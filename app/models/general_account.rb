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

  # Le compte courant entre les entités de la maison. Une charge de la Société
  # simple payée depuis le compte de la Fondation crée une dette réelle entre
  # elles : sans ce compte, il faudrait ranger la charge chez la mauvaise entité
  # ou faire disparaître la dette. Son solde est ce qu'une entité doit à l'autre.
  INTER_ENTITY_CODE = "416100".freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  has_many :journal_lines, dependent: :restrict_with_error
  has_many :cash_accounts, dependent: :restrict_with_error

  # La classe et la nature se lisent dans le NUMÉRO — c'est toute la logique du
  # PCMN, et la reprise d'un plan comptable de 146 comptes ne va pas les
  # ressaisir un par un. Les classes 4 et 5 sont les seules ambiguës : un compte
  # de tiers peut être une créance ou une dette selon son sens, donc la reprise
  # doit le préciser, faute de quoi on retient l'actif — le cas majoritaire.
  NATURE_BY_KLASS = {
    1 => "equity", 2 => "asset", 3 => "asset", 4 => "asset",
    5 => "asset", 6 => "expense", 7 => "revenue"
  }.freeze

  def self.klass_from(code) = code.to_s[0].to_i
  def self.nature_from(code) = NATURE_BY_KLASS[klass_from(code)]

  before_validation :infer_klass_and_nature, on: :create

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

  private

  # Une valeur explicitement fournie l'emporte toujours : la déduction est un
  # confort de reprise, pas une règle qui écrase ce qu'un comptable a décidé.
  def infer_klass_and_nature
    return if code.blank?

    self.klass = self.class.klass_from(code) if klass.blank?
    self.nature = self.class.nature_from(code) if nature.blank?
  end
end
