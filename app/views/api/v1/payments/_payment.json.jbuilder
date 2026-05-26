json.id payment.id
json.type "payment"
json.amount { json.partial! "api/v1/shared/money", money: payment.amount }
json.status payment.status
json.payment_method payment.payment_method
if payment.booking
  json.booking do
    json.id payment.booking_id
    json.name payment.booking.group_name.presence || payment.booking.name
  end
else
  json.booking nil
end
json.created_at payment.created_at
json.updated_at payment.updated_at
json.url api_v1_payment_url(payment)
