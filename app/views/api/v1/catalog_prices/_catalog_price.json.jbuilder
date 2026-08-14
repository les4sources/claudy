json.id catalog_price.id
json.type "catalog_price"
json.catalog_item_id catalog_price.catalog_item_id
json.active_from catalog_price.active_from
json.active_until catalog_price.active_until
json.open_ended catalog_price.open_ended?
json.current catalog_price.current?
json.member_price { json.partial! "api/v1/shared/money", money: catalog_price.member_price }
json.purchase_price { json.partial! "api/v1/shared/money", money: catalog_price.purchase_price }
json.reference_price { json.partial! "api/v1/shared/money", money: catalog_price.reference_price }
json.public_price { json.partial! "api/v1/shared/money", money: catalog_price.public_price }
json.note catalog_price.note
json.created_at catalog_price.created_at
json.updated_at catalog_price.updated_at
