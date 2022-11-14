class EventCategory < ApplicationRecord
  has_many :events, dependent: :nullify

  validates :name, presence: true
end
