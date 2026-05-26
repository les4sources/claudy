json.data @bookings do |booking|
  json.partial! "api/v1/bookings/booking", booking: booking, detailed: false
end
json.meta { json.partial! "api/v1/shared/pagination", collection: @bookings }
