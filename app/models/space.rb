class Space < ApplicationRecord
  has_many :space_reservations

  has_soft_deletion default_scope: true
end
