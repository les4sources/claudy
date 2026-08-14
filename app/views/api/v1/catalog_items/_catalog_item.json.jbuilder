json.id catalog_item.id
json.type "catalog_item"
json.name catalog_item.name
json.channel catalog_item.channel
json.channel_label catalog_item.channel_label
json.category catalog_item.category
json.unit catalog_item.unit
json.unit_label catalog_item.unit_label
json.reference catalog_item.reference
json.active catalog_item.active

price = catalog_item.price_on(on)
json.price_on on
if price
  json.price { json.partial! "api/v1/catalog_prices/catalog_price", catalog_price: price }
else
  json.price nil
end

json.created_at catalog_item.created_at
json.updated_at catalog_item.updated_at
json.url api_v1_catalog_item_url(catalog_item)
