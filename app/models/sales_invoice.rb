# Une facture de vente enregistrée dans Claudy (epic #240, phase 6).
#
# **Claudy n'émet pas de facture de vente.** Elles sortent d'OkiOki, qui n'a
# pas d'API : on en enregistre ici le numéro, la date, le montant et le PDF,
# et on les relie à ce qu'elles facturent. Le registre sert à trois choses —
# retrouver une facture, savoir si elle est payée, et garantir qu'un séjour
# n'est jamais facturé deux fois.
#
# AUCUNE ÉCRITURE COMPTABLE n'est générée (décision 8) : la recette est déjà au
# grand livre par la ventilation de la ligne bancaire. Une écriture de vente en
# plus compterait la même recette deux fois.
#
# Le paiement est un RAPPROCHEMENT, jamais une case cochée (décision 4) : une
# facture passe `paid` quand les lignes de trésorerie affectées sur elle
# couvrent son total, et redevient `issued` si on défait l'affectation.
class SalesInvoice < ApplicationRecord
  STATUSES = %w[issued paid].freeze

  STATUS_LABELS = {
    "issued" => "Émise",
    "paid" => "Payée"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :legal_entity
  belongs_to :customer, optional: true
  has_many :sales_invoice_sources, dependent: :destroy
  # Les lignes de trésorerie affectées sur cette facture : c'est elles qui
  # disent si elle est payée.
  has_many :cash_allocations, as: :document, dependent: :nullify

  has_one_attached :document

  monetize :total_cents

  validates :number, presence: true
  validates :number, uniqueness: { scope: :legal_entity_id, message: "existe déjà pour cette entité" }
  validates :issued_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :total_cents, numericality: { only_integer: true, greater_than: 0 }

  scope :ordered, -> { order(issued_on: :desc, id: :desc) }
  scope :issued, -> { where(status: "issued") }
  scope :paid, -> { where(status: "paid") }
  scope :in_period, ->(from, to) { where(issued_on: from..to) }

  def status_label = STATUS_LABELS.fetch(status, status)
  def issued? = status == "issued"
  def paid? = status == "paid"

  def label = "Facture #{number}"

  # Les objets facturés — un séjour, un ou plusieurs réservables d'espace.
  def sources = sales_invoice_sources.map(&:source).compact

  def stay_sources = sources.grep(Stay)

  # Le client affiché : celui de la facture, sinon celui du séjour facturé.
  def customer_name
    return customer.decorate.display_name if customer && customer.respond_to?(:decorate)

    stay_sources.first&.customer&.then { |c| c.try(:organization_name).presence } ||
      [customer&.first_name, customer&.last_name].compact.join(" ").presence
  end

  def allocated_cents = cash_allocations.sum(:amount_cents)
end
