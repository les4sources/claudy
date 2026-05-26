json.id space_booking.id
json.type "space_booking"
json.group_name space_booking.group_name
json.firstname space_booking.firstname
json.lastname space_booking.lastname
json.name space_booking.name
json.email space_booking.email
json.phone space_booking.phone
json.from_date space_booking.from_date
json.to_date space_booking.to_date
json.status space_booking.status
json.payment_status space_booking.payment_status
json.invoice_status space_booking.invoice_status
json.contract_status space_booking.contract_status
json.persons space_booking.persons
json.arrival_time space_booking.arrival_time
json.departure_time space_booking.departure_time
json.tier space_booking.tier
json.event_id space_booking.event_id

json.price { json.partial! "api/v1/shared/money", money: space_booking.price }
json.paid_amount { json.partial! "api/v1/shared/money", money: space_booking.paid_amount }
json.deposit_amount { json.partial! "api/v1/shared/money", money: space_booking.deposit_amount }
json.advance_amount { json.partial! "api/v1/shared/money", money: space_booking.advance_amount }

json.options do
  json.kitchenware space_booking.option_kitchenware
  json.beamer space_booking.option_beamer
  json.wifi space_booking.option_wifi
  json.tables space_booking.option_tables
end

json.spaces space_booking.spaces do |space|
  json.partial! "api/v1/shared/ref", record: space
end

json.token space_booking.token
json.created_at space_booking.created_at
json.updated_at space_booking.updated_at
json.url api_v1_space_booking_url(space_booking)

if detailed
  json.notes space_booking.notes
  json.public_notes space_booking.public_notes.respond_to?(:to_plain_text) ? space_booking.public_notes.to_plain_text : space_booking.public_notes
  json.space_reservations space_booking.space_reservations.to_a.reject { |r| r.deleted_at.present? } do |reservation|
    json.date reservation.date
    json.duration reservation.duration
    json.space { json.partial! "api/v1/shared/ref", record: reservation.space }
  end
end
