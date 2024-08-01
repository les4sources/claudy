module StayStatus
  PENDING = 'pending'
  CONFIRMED = 'confirmed'
  CANCELED = 'canceled'
  COMPLETED = 'completed'
  DECLINED = 'declined'

  ALL_STATUSES = [PENDING, CONFIRMED, CANCELED, COMPLETED, DECLINED].freeze
end