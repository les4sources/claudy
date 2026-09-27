json.id plant_variety.id
json.type "plant_variety"
json.name plant_variety.name
json.full_name plant_variety.full_name
json.notes plant_variety.notes
json.plant_species_id plant_variety.plant_species_id
json.species do
  json.id plant_variety.plant_species&.id
  json.name plant_variety.plant_species&.name
  json.latin_name plant_variety.plant_species&.latin_name
end
json.created_at plant_variety.created_at
json.updated_at plant_variety.updated_at
