class Unavailability < ApplicationRecord
  validates :date,
            presence: true
  belongs_to :lodging
end
