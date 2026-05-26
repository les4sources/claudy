json.data @lodgings do |lodging|
  json.partial! "api/v1/lodgings/lodging", lodging: lodging, detailed: false
end
json.meta { json.partial! "api/v1/shared/pagination", collection: @lodgings }
