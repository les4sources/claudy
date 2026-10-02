# Une demande de reconstruction du site les4sources.be — voir `WebsiteRebuildJob`.
#
# Cycle : `pending` (des sauvegardes s'accumulent pendant la fenêtre de
# regroupement) → `dispatching` (le job l'a prise) → `sent`, `failed` ou
# `skipped` (pas d'URL de webhook, ou environnement hors production). Une
# seule demande est en attente à la fois : les sauvegardes suivantes la
# rejoignent (`requests_count`).
# == Schema Information
#
# Table name: website_rebuilds
#
#  id                :bigint           not null, primary key
#  dispatched_at     :datetime
#  error_message     :string
#  last_requested_at :datetime         not null
#  requested_at      :datetime         not null
#  requests_count    :integer          default(1), not null
#  response_code     :string
#  status            :string           default("pending"), not null
#  trigger           :string           default("publication"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_website_rebuilds_on_status_and_requested_at  (status,requested_at)
#
class WebsiteRebuild < ApplicationRecord
  STATUSES = %w[pending dispatching sent failed skipped].freeze
  TRIGGERS = %w[publication api recovery].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :trigger, inclusion: { in: TRIGGERS }

  scope :pending, -> { where(status: "pending") }
  scope :recent, -> { order(requested_at: :desc, id: :desc) }

  # Rejoint la demande en attente, ou en ouvre une. Renvoie [demande, créée?].
  def self.request!(trigger: "publication")
    transaction do
      now = Time.current
      waiting = pending.order(:requested_at).lock.first
      if waiting
        waiting.update!(last_requested_at: now, requests_count: waiting.requests_count + 1)
        [waiting, false]
      else
        [create!(trigger: trigger, requested_at: now, last_requested_at: now), true]
      end
    end
  end
end
