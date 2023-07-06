class EventCategory < ApplicationRecord
  has_many :events, dependent: :nullify

  has_paper_trail
  has_soft_deletion default_scope: true

  validates :name, presence: true
end
