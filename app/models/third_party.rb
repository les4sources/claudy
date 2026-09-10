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
#  email       :string
#  iban        :string
#  kind        :string           not null
#  name        :string           not null
#  notes       :text
#  vat_number  :string
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

  KIND_LABELS = {
    "supplier" => "Fournisseur",
    "customer" => "Client",
    "both" => "Les deux"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  # Comme pour un artisan : une coordonnée bancaire n'a pas à être lisible dans
  # un dump de base.
  encrypts :iban

  belongs_to :customer, optional: true
  belongs_to :human, optional: true
  has_many :journal_lines, dependent: :restrict_with_error

  before_validation :normalize_iban
  before_validation :assign_code, on: :create

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :iban, iban: true, allow_blank: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :ordered, -> { order(:name) }
  scope :actives, -> { where(active: true) }
  scope :suppliers, -> { where(kind: %w[supplier both]) }
  scope :customers, -> { where(kind: %w[customer both]) }
  scope :search, ->(query) {
    like = "%#{query.to_s.strip}%"
    where("third_parties.name ILIKE :q OR third_parties.code ILIKE :q", q: like)
  }

  def to_s = name

  def kind_label = KIND_LABELS.fetch(kind, kind)

  # L'IBAN ne s'affiche jamais en entier hors du formulaire : quatre caractères
  # suffisent à reconnaître le compte sans l'exposer.
  def iban_masked
    return nil if iban.blank?

    "•••• #{iban.last(4)}"
  end

  # Le tiers d'un membre. La reprise Winbooks a créé des tiers depuis des codes
  # (`MICHAELHUL`) sans savoir à qui ils correspondaient : on cherche donc
  # d'abord le rattachement explicite, jamais le nom.
  def self.for_human!(human)
    raise ArgumentError, "Un tiers de membre a besoin d'une personne" if human.nil?

    existing = find_by(human_id: human.id)
    return existing if existing

    create!(human: human, kind: "supplier",
            name: human.name.presence || "Membre ##{human.id}",
            email: human.email.presence)
  end

  # Un code lisible dérivé du nom, et unique. Winbooks en produisait de la même
  # famille (`ANTARGAZ`) : garder cette forme évite de dérouter la trésorière.
  def self.code_for(name)
    base = I18n.transliterate(name.to_s).upcase.gsub(/[^A-Z0-9]/, "").first(10)
    base = "TIERS" if base.blank?

    # L'index d'unicité du code porte sur TOUTES les lignes, y compris les
    # soft-deletées : on cherche donc hors du `default_scope`.
    candidate = base
    suffix = 1
    while unscoped.where(code: candidate).exists?
      suffix += 1
      candidate = "#{base.first(9)}#{suffix}"
    end
    candidate
  end

  private

  def normalize_iban
    self.iban = iban.to_s.gsub(/\s+/, "").upcase.presence
  end

  def assign_code
    self.code = self.class.code_for(name) if code.blank?
  end
end
