class Booking < ApplicationRecord
  monetize :price_cents
end
