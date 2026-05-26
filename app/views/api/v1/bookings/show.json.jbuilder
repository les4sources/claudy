json.data do
  json.partial! "api/v1/bookings/booking", booking: @booking, detailed: true
end
