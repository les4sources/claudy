class StayItem < ApplicationRecord
  belongs_to :stay
  belongs_to :bookable, polymorphic: true
end