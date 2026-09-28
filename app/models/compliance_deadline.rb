# Une échéance de l'échéancier comptable : une occurrence d'une
# `ComplianceObligation` — « TVA T3 2026 de la SRL, pour le 20 octobre ».
#
# Elle naît du générateur, jamais d'un formulaire : c'est ce qui empêche le
# doublon qui traînait dans Notion. On y modifie ce qui s'écarte de la règle —
# la date, l'état, une note, la preuve du dépôt.
#
# UNE ÉCHÉANCE DE PAIEMENT SE SOLDE PAR SA FACTURE (contrat `Payable`, epic
# #240 décision 4). Le précompte immobilier n'est pas « fait » parce qu'on a
# coché une case : il l'est quand l'avertissement-extrait de rôle, encodé en
# facture d'achat et lié ici, est rapproché de sa ligne bancaire. L'état est
# donc DÉDUIT de la facture (`effective_status`) et jamais recopié : si on défait
# le rapprochement, l'échéance redevient à faire d'elle-même.
# == Schema Information
#
# Table name: compliance_deadlines
#
#  id                       :bigint           not null, primary key
#  deleted_at               :datetime
#  done_on                  :date
#  due_on                   :date             not null
#  last_reminded_on         :date
#  last_reminder_stage      :string
#  note                     :text
#  period_start             :date             not null
#  status                   :string           default("todo"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  compliance_obligation_id :bigint           not null
#  done_by_user_id          :bigint
#  purchase_invoice_id      :bigint
#
# Indexes
#
#  index_compliance_deadlines_on_compliance_obligation_id  (compliance_obligation_id)
#  index_compliance_deadlines_on_deleted_at                (deleted_at)
#  index_compliance_deadlines_on_done_by_user_id           (done_by_user_id)
#  index_compliance_deadlines_on_due_on                    (due_on)
#  index_compliance_deadlines_on_obligation_and_period     (compliance_obligation_id,period_start) UNIQUE WHERE (deleted_at IS NULL)
#  index_compliance_deadlines_on_purchase_invoice_id       (purchase_invoice_id)
#
# Foreign Keys
#
#  fk_rails_...  (compliance_obligation_id => compliance_obligations.id)
#  fk_rails_...  (done_by_user_id => users.id)
#  fk_rails_...  (purchase_invoice_id => purchase_invoices.id)
#
class ComplianceDeadline < ApplicationRecord
  STATUSES = %w[todo in_progress done not_applicable].freeze
  STATUS_LABELS = {
    "todo" => "À faire",
    "in_progress" => "En cours",
    "done" => "Fait",
    "not_applicable" => "Sans objet"
  }.freeze
  CLOSED_STATUSES = %w[done not_applicable].freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :compliance_obligation
  belongs_to :done_by_user, class_name: "User", optional: true
  belongs_to :purchase_invoice, optional: true

  # La preuve : l'accusé Intervat, le récépissé du greffe, le PV signé.
  has_one_attached :proof

  delegate :legal_entity, :title, :payment?, to: :compliance_obligation

  validates :status, inclusion: { in: STATUSES }
  validates :period_start, :due_on, presence: true
  validate :invoice_only_for_payment

  scope :ordered, -> { order(:due_on, :id) }
  # Ouverte = ni fermée à la main, ni soldée par sa facture. Le second test
  # passe par une jointure : c'est la facture qui fait foi, pas un statut copié.
  scope :outstanding, lambda {
    left_joins(:purchase_invoice)
      .where.not(status: CLOSED_STATUSES)
      .where("compliance_deadlines.purchase_invoice_id IS NULL OR purchase_invoices.status <> 'paid'")
  }
  scope :for_entity, ->(entity_id) { joins(:compliance_obligation).where(compliance_obligations: { legal_entity_id: entity_id }) }
  scope :payments, -> { joins(:compliance_obligation).where(compliance_obligations: { payment: true }) }

  def settled_by_invoice? = purchase_invoice&.paid? || false

  def effective_status = settled_by_invoice? ? "done" : status
  def status_label = STATUS_LABELS.fetch(effective_status, effective_status)
  def closed? = CLOSED_STATUSES.include?(effective_status)
  def open? = !closed?

  def effective_done_on = settled_by_invoice? ? purchase_invoice.paid_on : done_on

  def overdue?(on = Date.current) = open? && due_on < on
  def days_left(on = Date.current) = (due_on - on).to_i

  def period_label = compliance_obligation.period_label(period_start)
  def display_title = [title, period_label].compact.join(" — ")

  # Clore à la main. La date est celle du geste, pas celle de l'échéance : une
  # TVA déposée en retard doit se lire en retard.
  def close!(status:, user: nil, on: Date.current)
    update!(status: status, done_on: on, done_by_user: user)
  end

  def reopen!
    update!(status: "todo", done_on: nil, done_by_user: nil)
  end

  private

  # Lier une facture à une échéance qui n'est pas un paiement la ferait se
  # solder par un rapprochement qui ne la concerne pas.
  def invoice_only_for_payment
    return if purchase_invoice_id.blank? || compliance_obligation.nil? || payment?

    errors.add(:purchase_invoice, "ne se lie qu'à une échéance de paiement")
  end
end
