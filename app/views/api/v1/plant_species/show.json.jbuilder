json.data { json.partial! "api/v1/plant_species/plant_species", plant_species: @plant_species }
json.meta { json.created @created } unless @created.nil?
