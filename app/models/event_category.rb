# == Schema Information
#
# Table name: event_categories
#
#  id         :integer          not null, primary key
#  name       :string
#  color      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  deleted_at :datetime
#
class EventCategory < ApplicationRecord
  has_many :events, dependent: :nullify

  has_paper_trail
  has_soft_deletion default_scope: true

  validates :name, presence: true
end
