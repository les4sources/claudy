# == Schema Information
#
# Table name: gathering_categories
#
#  id                       :bigint           not null, primary key
#  color                    :string           not null
#  default_duration_minutes :integer
#  default_start_time       :time
#  deleted_at               :datetime
#  name                     :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
class GatheringCategory < ApplicationRecord
  has_many :gatherings, dependent: :nullify

  has_paper_trail
  has_soft_deletion default_scope: true

  validates :name, :color, presence: true
  validates :default_duration_minutes,
            numericality: { greater_than: 0 },
            allow_nil: true

  scope :ordered, -> { order(:name) }

  def variable_time?
    default_start_time.nil?
  end
end
