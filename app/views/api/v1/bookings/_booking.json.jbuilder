json.id booking.id
json.type "booking"
json.group_name booking.group_name
json.firstname booking.firstname
json.lastname booking.lastname
json.name booking.name
json.email booking.email
json.phone booking.phone
json.from_date booking.from_date
json.to_date booking.to_date
json.nights_count booking.nights_count
json.status booking.status
json.payment_status booking.payment_status
json.invoice_status booking.invoice_status
json.contract_status booking.contract_status
json.adults booking.adults
json.children booking.children
json.babies booking.babies
json.beds_count(booking.adults.to_i + booking.children.to_i)
json.tier booking.tier
json.platform booking.platform
json.estimated_arrival booking.estimated_arrival
json.departure_time booking.departure_time

if booking.lodging
  json.lodging { json.partial! "api/v1/shared/ref", record: booking.lodging }
else
  json.lodging nil
end

json.price { json.partial! "api/v1/shared/money", money: booking.price }

json.options do
  json.partyhall booking.option_partyhall
  json.pizza_party booking.option_pizza_party
  json.bread booking.option_bread
  json.babysitting booking.option_babysitting
  json.discgolf booking.option_discgolf
  json.bedsheets booking.bedsheets
  json.towels booking.towels
  json.wifi booking.wifi
end

json.token booking.token
json.created_at booking.created_at
json.updated_at booking.updated_at
json.url api_v1_booking_url(booking)

if detailed
  json.notes booking.notes
  json.comments booking.comments
  json.public_notes booking.public_notes.respond_to?(:to_plain_text) ? booking.public_notes.to_plain_text : booking.public_notes
  json.reservations booking.reservations.to_a.reject { |r| r.deleted_at.present? } do |reservation|
    json.date reservation.date
    json.room { json.partial! "api/v1/shared/ref", record: reservation.room }
  end
end
