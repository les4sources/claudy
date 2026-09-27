json.data @plant_varieties do |plant_variety|
  json.partial! "api/v1/plant_varieties/plant_variety", plant_variety: plant_variety
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @plant_varieties }
