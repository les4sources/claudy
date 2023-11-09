class HumanRole < ApplicationRecord
  belongs_to :human
  belongs_to :role

  validates :date, presence: true
end
