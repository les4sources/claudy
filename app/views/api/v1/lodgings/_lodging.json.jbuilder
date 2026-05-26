json.id lodging.id
json.type "lodging"
json.name lodging.name
json.summary lodging.summary
json.description lodging.description
json.price_night { json.partial! "api/v1/shared/money", money: lodging.price_night }
json.weekend_discount_cents lodging.weekend_discount_cents
json.party_hall_availability lodging.party_hall_availability
json.available_for_bookings lodging.available_for_bookings
json.show_on_reports lodging.show_on_reports
json.created_at lodging.created_at
json.updated_at lodging.updated_at
json.url api_v1_lodging_url(lodging)

if detailed
  json.rooms lodging.rooms do |room|
    json.partial! "api/v1/rooms/room", room: room
  end
end
