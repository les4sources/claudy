json.data do
  json.partial! "api/v1/space_bookings/space_booking", space_booking: @space_booking, detailed: true
end
