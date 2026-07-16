# == Schema Information
#
# Table name: experience_bookings
#
#  id                          :bigint           not null, primary key
#  experience_availability_id  :bigint           not null
#  stay_id                     :bigint           not null
#  participants                :integer
#  status                      :string           default("pending")
#  notes                       :text
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#
class ExperienceBooking < ApplicationRecord
  STATUSES = %w[pending confirmed cancelled].freeze

  belongs_to :experience_availability
  belongs_to :stay

  delegate :experience, to: :experience_availability

  validates :participants, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  before_validation :set_default_status

  scope :active, -> { where.not(status: "cancelled") }

  def pending?   = status == "pending"
  def confirmed? = status == "confirmed"
  def cancelled? = status == "cancelled"

  # Montant TVAC de l'activité réservée (epic #55, Phase 1). Délègue au service
  # `Pricing::ExperienceLine`, source de vérité unique du barème « forfait fixe
  # + €/pers ». `experience` est délégué depuis `experience_availability`.
  def price_cents
    Pricing::ExperienceLine.amount_cents(experience, participants: participants)
  end

  private

  def set_default_status
    self.status ||= "pending"
  end
end
