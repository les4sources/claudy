json.id plant_species.id
json.type "plant_species"
json.name plant_species.name
json.latin_name plant_species.latin_name
json.full_name plant_species.full_name
json.family plant_species.family
json.common_names plant_species.common_names
json.hardiness plant_species.hardiness
json.height plant_species.height
json.spread plant_species.spread
json.exposure plant_species.exposure
json.edible_parts plant_species.edible_parts
json.wikipedia_url plant_species.wikipedia_url
json.notes plant_species.notes
json.harvest_windows plant_species.harvest_windows do |window|
  json.partial! "api/v1/plant_harvest_windows/window", window: window
end
json.varieties plant_species.varieties do |variety|
  json.id variety.id
  json.name variety.name
end
json.created_at plant_species.created_at
json.updated_at plant_species.updated_at
