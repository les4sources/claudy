json.data @plants do |plant|
  json.partial! "api/v1/plants/plant", plant: plant
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @plants }
