# Une ligne du relevé de dépôt-vente : un article, une quantité, un prix unitaire
# (epic #248, phase 2 ; epic #359, phase 1).
#
# Le montant est CALCULÉ et stocké : l'artisan ne le tape pas, et il reste lisible
# tel quel dans dix-huit mois même si on change la façon de le calculer.
#
# L'article du catalogue est FACULTATIF et le libellé reste roi : la ligne copie
# le nom et le prix du jour de l'article à sa création, puis vit sa vie. Un
# artisan qui renomme son savon ou qui monte son prix ne réécrit pas ce qu'il a
# déclaré le mois dernier.
# == Schema Information
#
# Table name: consignment_report_lines
#
#  id                    :bigint           not null, primary key
#  amount_cents          :integer          default(0), not null
#  deleted_at            :datetime
#  label                 :string           not null
#  payment_method        :string
#  position              :integer          default(0), not null
#  quantity              :integer          default(1), not null
#  unit_price_cents      :integer          default(0), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  catalog_item_id       :bigint
#  consignment_report_id :bigint           not null
#
# Indexes
#
#  index_consignment_lines_on_catalog_item  (catalog_item_id)
#  index_consignment_lines_on_deleted_at    (deleted_at)
#  index_consignment_lines_on_report        (consignment_report_id)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_item_id => catalog_items.id)
#  fk_rails_...  (consignment_report_id => consignment_reports.id)
#
class ConsignmentReportLine < ApplicationRecord
  # Comment le client a payé cette ligne (décision 6) : c'est cette colonne qui
  # permet, au mois, de confronter le total des feuilles aux virements reçus et
  # aux espèces (phases 4 et 5).
  PAYMENT_METHODS = %w[qr transfer cash].freeze
  PAYMENT_METHOD_LABELS = {
    "qr" => "QR bancaire", "transfer" => "Virement", "cash" => "Espèces"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :consignment_report
  belongs_to :catalog_item, optional: true

  before_validation :copy_from_catalog_item, on: :create
  before_validation :compute_amount

  validates :label, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }, allow_blank: true
  validate :catalog_item_belongs_to_consignor

  scope :ordered, -> { order(:position, :id) }
  scope :paid_in_cash, -> { where(payment_method: "cash") }

  def payment_method_label = PAYMENT_METHOD_LABELS[payment_method]

  private

  # Le libellé et le prix viennent de l'article quand il est là et que l'artisan
  # ne les a pas tapés lui-même. Le prix du jour est le prix public : c'est ce
  # que le client a payé en rayon.
  #
  # À LA CRÉATION seulement : une ligne déjà enregistrée ne se fait jamais
  # rattraper par le catalogue. Un prix à zéro saisi d'emblée est donc lu comme
  # « pas encore rempli » (c'est la valeur par défaut de la colonne) ; offrir un
  # article se fait en corrigeant la ligne, qui ne recopie plus rien.
  def copy_from_catalog_item
    return if catalog_item.blank?

    self.label = catalog_item.name if label.blank?
    # `unit_price_cents` vaut 0 par défaut en base : `present?` y répondrait
    # toujours oui. Ce qui compte est qu'on l'ait ASSIGNÉ — un artisan qui tape
    # son prix garde le sien, y compris un cadeau à 0 €.
    return if unit_price_cents_changed?

    price = catalog_item.price_on(Date.current)
    self.unit_price_cents = price&.public_price_cents || price&.member_price_cents
  end

  # Cloison (epic #359, phase 2) : une ligne ne pointe que sur un article de
  # l'artisan du relevé. Le formulaire ne propose que les siens, mais un
  # identifiant forgé ne doit pas rattacher la vente au savon d'un autre.
  def catalog_item_belongs_to_consignor
    return if catalog_item.blank? || consignment_report.blank?
    return if catalog_item.consignor_id == consignment_report.consignor_id

    errors.add(:catalog_item_id, "n'est pas un de vos produits")
  end

  def compute_amount
    self.quantity = 1 if quantity.blank?
    self.unit_price_cents = 0 if unit_price_cents.blank?
    self.amount_cents = quantity.to_i * unit_price_cents.to_i
  end
end
