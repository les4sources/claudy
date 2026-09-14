# Un artisan qui dépose des produits en dépôt-vente dans l'armoire de
# l'épicerie (epic #248, décision 1). Il gère son stock lui-même ; chaque mois
# il déclare ce qu'il a vendu et les 4 Sources lui reversent sa part.
#
# Deux modes de règlement, qui ne changent rien à la déclaration mais tout à ce
# qui suit : `invoice`, l'artisan indépendant nous envoie sa facture (c'est une
# facture d'achat comme une autre) ; `transfer`, on lui vire son net — d'où
# l'IBAN, obligatoire dans ce mode et chiffré au repos.
#
# Les relevés mensuels (`ConsignmentReport`, phase 2) portent ce qui a été vendu
# chaque mois, déclaré par l'artisan lui-même.
# == Schema Information
#
# Table name: consignors
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  commission_percent :integer          default(20), not null
#  deleted_at         :datetime
#  email              :string
#  ends_on            :date
#  iban               :text
#  name               :string           not null
#  notes              :text
#  settlement_mode    :string           default("transfer"), not null
#  starts_on          :date
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  human_id           :bigint
#  third_party_id     :bigint
#
# Indexes
#
#  index_consignors_on_active          (active)
#  index_consignors_on_deleted_at      (deleted_at)
#  index_consignors_on_human_id        (human_id)
#  index_consignors_on_third_party_id  (third_party_id)
#
# Foreign Keys
#
#  fk_rails_...  (human_id => humans.id)
#  fk_rails_...  (third_party_id => third_parties.id)
#
class Consignor < ApplicationRecord
  SETTLEMENT_MODES = %w[invoice transfer].freeze

  SETTLEMENT_MODE_LABELS = {
    "invoice"  => "L'artisan facture",
    "transfer" => "Virement des 4 Sources"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  encrypts :iban

  belongs_to :human,       optional: true
  belongs_to :third_party, optional: true
  has_many :consignment_reports, dependent: :destroy

  before_validation :normalize_iban
  before_validation :inherit_human_identity, on: :create

  validates :name, presence: true
  validates :settlement_mode, inclusion: { in: SETTLEMENT_MODES }
  validates :commission_percent,
            numericality: { only_integer: true,
                            greater_than_or_equal_to: 0,
                            less_than_or_equal_to: 100 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :iban, iban: true, allow_blank: true
  validates :iban, presence: { message: "est obligatoire pour un règlement par virement" },
                   if: :transfer?
  validate :ends_after_starts

  scope :ordered, -> { order(active: :desc, name: :asc) }
  scope :actives, -> { where(active: true) }

  def last_report = consignment_reports.ordered.first

  def transfer? = settlement_mode == "transfer"
  def invoice?  = settlement_mode == "invoice"

  def settlement_mode_label = SETTLEMENT_MODE_LABELS.fetch(settlement_mode, settlement_mode)

  # L'IBAN ne s'affiche jamais en entier hors du formulaire : quatre derniers
  # caractères suffisent à reconnaître le compte sans l'exposer.
  def iban_masked
    return nil if iban.blank?

    "•••• #{iban.last(4)}"
  end

  # Contrat en cours à cette date : commencé, pas terminé, et actif.
  def running_on?(date = Date.current)
    return false unless active?
    return false if starts_on.present? && date < starts_on
    return false if ends_on.present? && date > ends_on

    true
  end

  private

  def normalize_iban
    self.iban = iban.to_s.gsub(/\s+/, "").upcase.presence
  end

  # « Lien facultatif vers un Human (pré-remplit nom et email) » : le formulaire
  # le fait en direct, le modèle rattrape une création faite ailleurs (import,
  # console) pour qu'un artisan lié n'arrive jamais sans nom.
  def inherit_human_identity
    return if human.blank?

    self.name  = human.name  if name.blank?
    self.email = human.email if email.blank?
  end

  def ends_after_starts
    return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

    errors.add(:ends_on, "doit être postérieure à la date de début")
  end
end
