json.data @catalog_items do |catalog_item|
  json.partial! "api/v1/catalog_items/catalog_item", catalog_item: catalog_item, on: @on
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @catalog_items }
