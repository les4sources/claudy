json.id stay.id
json.type "stay"
json.status stay.status
json.arrival_date stay.arrival_date
json.departure_date stay.departure_date
json.total_amount { json.partial! "api/v1/shared/money", money: stay.total_amount }
json.legacy_origin stay.legacy_origin
json.customer do
  json.id stay.customer_id
  json.name stay.customer&.name
end
json.created_at stay.created_at
json.updated_at stay.updated_at
json.url api_v1_stay_url(stay)

json.items stay.stay_items do |item|
  json.id item.id
  json.bookable_type item.bookable_type
  json.bookable_id item.bookable_id
  bookable = item.bookable
  if bookable
    json.from_date bookable.try(:from_date)
    json.to_date bookable.try(:to_date)
    json.status bookable.try(:status)
  end
end

if detailed
  json.items_count stay.stay_items.size
end
