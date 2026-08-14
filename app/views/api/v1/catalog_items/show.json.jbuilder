json.data do
  json.partial! "api/v1/catalog_items/catalog_item", catalog_item: @catalog_item, on: @on
  json.prices @catalog_item.prices_history do |catalog_price|
    json.partial! "api/v1/catalog_prices/catalog_price", catalog_price: catalog_price
  end
end
json.meta { json.created @created } unless @created.nil?
