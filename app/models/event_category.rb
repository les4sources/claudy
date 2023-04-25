class EventCategory < ApplicationRecord
  has_many :events, dependent: :nullify

  has_paper_trail

  validates :name, presence: true
end
