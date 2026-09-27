json.data { json.partial! "api/v1/plant_varieties/plant_variety", plant_variety: @plant_variety }
json.meta { json.created @created } unless @created.nil?
