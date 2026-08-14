json.data @catalog_prices do |catalog_price|
  json.partial! "api/v1/catalog_prices/catalog_price", catalog_price: catalog_price
end
