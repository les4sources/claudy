# == Schema Information
#
# Table name: gatherings
#
#  id                    :bigint           not null, primary key
#  name                  :string
#  gathering_category_id :bigint           not null
#  starts_at             :datetime         not null
#  ends_at               :datetime         not null
#  location              :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  deleted_at            :datetime
#
class Gathering < ApplicationRecord
  include PublicActivity::Model
  tracked owner: Proc.new { |controller, _model| controller.current_user rescue nil }

  belongs_to :gathering_category
  has_many :agenda_items, -> { ordered }, dependent: :destroy
  has_many :decisions, dependent: :nullify

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :notes

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
