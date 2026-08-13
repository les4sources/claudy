# == Schema Information
#
# Table name: gatherings
#
#  id                    :bigint           not null, primary key
#  deleted_at            :datetime
#  ends_at               :datetime         not null
#  location              :string
#  name                  :string
#  starts_at             :datetime         not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  gathering_category_id :bigint           not null
#
# Indexes
#
#  index_gatherings_on_gathering_category_id  (gathering_category_id)
#  index_gatherings_on_starts_at_and_ends_at  (starts_at,ends_at)
#
# Foreign Keys
#
#  fk_rails_...  (gathering_category_id => gathering_categories.id)
#
class Gathering < ApplicationRecord
  include PublicActivity::Model
  tracked owner: Proc.new { |controller, _model| controller.current_user rescue nil }

  belongs_to :gathering_category
  has_many :agenda_items, -> { ordered }, dependent: :destroy
  has_many :gathering_actions, -> { ordered }, dependent: :destroy
  has_many :decisions, dependent: :nullify

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :notes
  has_rich_text :report

  attr_accessor :starts_at_date, :starts_at_time, :ends_at_date, :ends_at_time

  validates :starts_at, :ends_at, presence: true
  validate  :ends_after_starts

  by_star_field :starts_at, :ends_at

  scope :upcoming, -> { where("ends_at >= ?", Time.current).order(:starts_at) }

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?
    errors.add(:ends_at, "doit être après le début") if ends_at < starts_at
  end
end
