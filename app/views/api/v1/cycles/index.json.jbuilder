json.data @cycles do |cycle|
  json.partial! "api/v1/cycles/cycle", cycle: cycle
end
json.meta { json.partial! "api/v1/shared/pagination", collection: @cycles }
