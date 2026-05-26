json.data @space_bookings do |space_booking|
  json.partial! "api/v1/space_bookings/space_booking", space_booking: space_booking, detailed: false
end
json.meta { json.partial! "api/v1/shared/pagination", collection: @space_bookings }
