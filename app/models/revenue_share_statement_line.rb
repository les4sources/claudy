# Une ligne de relevé de partage (issue #247).
#
# Deux natures, et la distinction n'est pas cosmétique :
#
# `booking` — la réservation elle-même, relevée pour le montant PERSISTÉ à son
# encodage. Un index unique partiel garantit qu'elle ne l'est qu'une fois : une
# nuitée payée deux fois aux propriétaires est une erreur qu'aucune relecture
# humaine ne rattrape trois mois plus tard.
#
# `adjustment` — la régularisation. Quand le prix d'une réservation déjà relevée
# change, on ne réécrit pas le relevé émis : on porte la DIFFÉRENCE au relevé
# suivant, en pointant la ligne d'origine.
# == Schema Information
#
# Table name: revenue_share_statement_lines
#
#  id                         :bigint           not null, primary key
#  amount_cents               :bigint           default(0), not null
#  deleted_at                 :datetime
#  from_date                  :date
#  kind                       :string           default("booking"), not null
#  label                      :string
#  to_date                    :date
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  booking_id                 :bigint           not null
#  origin_line_id             :bigint
#  revenue_share_statement_id :bigint           not null
#
# Indexes
#
#  index_revenue_share_statement_lines_on_booking_id      (booking_id)
#  index_revenue_share_statement_lines_on_deleted_at      (deleted_at)
#  index_revenue_share_statement_lines_on_origin_line_id  (origin_line_id)
#  index_rssl_on_statement_id                             (revenue_share_statement_id)
#  index_rssl_unique_booking_once                         (booking_id) UNIQUE WHERE (((kind)::text = 'booking'::text) AND (deleted_at IS NULL))
#
# Foreign Keys
#
#  fk_rails_...  (booking_id => bookings.id)
#  fk_rails_...  (origin_line_id => revenue_share_statement_lines.id)
#  fk_rails_...  (revenue_share_statement_id => revenue_share_statements.id)
#
class RevenueShareStatementLine < ApplicationRecord
  KINDS = %w[booking adjustment].freeze
  KIND_LABELS = {
    "booking"    => "Réservation",
    "adjustment" => "Régularisation"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :revenue_share_statement
  belongs_to :booking
  belongs_to :origin_line, class_name: "RevenueShareStatementLine", optional: true

  validates :kind, inclusion: { in: KINDS }

  scope :chronological, -> { order(:from_date, :id) }
  scope :bookings,      -> { where(kind: "booking") }
  scope :adjustments,   -> { where(kind: "adjustment") }

  def kind_label = KIND_LABELS.fetch(kind, kind)
  def adjustment? = kind == "adjustment"
end
