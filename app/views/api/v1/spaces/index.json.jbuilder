json.data @spaces do |space|
  json.partial! "api/v1/spaces/space", space: space
end
json.meta { json.partial! "api/v1/shared/pagination", collection: @spaces }
