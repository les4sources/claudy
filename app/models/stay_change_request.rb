# Demande de modification d'un séjour par le client (issue #133).
#
# C'est une DEMANDE, jamais une application directe : le séjour n'est TOUCHÉ
# qu'à l'approbation par l'équipe. Tant qu'elle est `pending`, la demande ne
# porte qu'un snapshot du draft proposé et les montants qui en découlent.
#
# Delta positif  → la différence s'ajoutera au solde exigible du séjour.
# Delta négatif avec trop-perçu → l'IBAN du client est exigé, et le
# remboursement est fait à la main par l'équipe dans les 10 jours qui suivent
# le séjour.
class StayChangeRequest < ApplicationRecord
  STATUSES = %w[pending approved refused].freeze

  # Formulaire IBAN volontairement PERMISSIF : 2 lettres de pays, 2 chiffres de
  # clé, puis 11 à 30 caractères alphanumériques. On valide la forme, pas la
  # clé de contrôle — un IBAN mal saisi sera vu par l'humain qui rembourse.
  IBAN_FORMAT = /\A[A-Z]{2}\d{2}[A-Z0-9]{11,30}\z/

  # Mention EXACTE affichée au client et recopiée dans la note interne.
  REFUND_NOTICE = "Le remboursement sera effectué dans les 10 jours qui suivent le séjour.".freeze

  belongs_to :stay

  has_paper_trail
  has_soft_deletion default_scope: true

  before_validation :normalize_iban

  validates :status, inclusion: { in: STATUSES }
  validates :new_total_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :refund_iban, format: { with: IBAN_FORMAT, message: "n'a pas un format valide" },
                          allow_blank: true
  validate :refund_iban_required_when_overpaid
  validate :only_one_pending_per_stay, on: :create

  scope :pending,  -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :refused,  -> { where(status: "refused") }

  def pending?  = status == "pending"
  def approved? = status == "approved"
  def refused?  = status == "refused"

  def increase? = delta_cents.to_i.positive?
  def decrease? = delta_cents.to_i.negative?

  # Trop-perçu : le client a déjà payé plus que le nouveau total. C'est LE cas
  # qui déclenche l'exigence d'un IBAN.
  def overpaid_cents
    [stay.amount_paid_cents.to_i - new_total_cents.to_i, 0].max
  end

  def refund_expected? = overpaid_cents.positive?

  # Le draft proposé, reconstruit pour le devis ou pour l'application.
  def proposed_draft
    Reservations::Draft.new(draft_snapshot)
  end

  private

  def normalize_iban
    self.refund_iban = refund_iban.to_s.gsub(/\s+/, "").upcase.presence
  end

  def refund_iban_required_when_overpaid
    return unless status == "pending"
    return unless stay.present?
    return unless refund_expected?
    return if refund_iban.present?

    errors.add(:refund_iban, "est obligatoire pour un remboursement")
  end

  # Une seule demande `pending` à la fois par séjour. Les demandes précédentes
  # sont retirées par le contrôleur AVANT la création (« la nouvelle remplace
  # l'ancienne ») ; cette validation est le filet.
  def only_one_pending_per_stay
    return unless status == "pending"
    return if stay.nil?
    return unless StayChangeRequest.pending.where(stay_id: stay_id).exists?

    errors.add(:base, "Une demande de modification est déjà en attente pour ce séjour")
  end
end
