json.id plant.id
json.type "plant"
json.name plant.name
json.display_name plant.display_name
# En nombre JSON (9.1, 12.0) ; `number_label` l'écrit comme sur le terrain (« 12 »).
json.number plant.number&.to_f
json.number_label plant.number_label
json.status plant.status
json.status_label plant.status_label
json.health plant.health
json.production plant.production
json.habit plant.habit
json.stratum plant.stratum
json.population plant.population
json.stock_type plant.stock_type
json.zone plant.zone
json.plant_count plant.plant_count
json.purchase_price_cents plant.purchase_price_cents
json.planted_on plant.planted_on
json.planted_year plant.planted_year
json.altitude plant.altitude
json.nursery plant.nursery
json.notion_url plant.notion_url
# Le texte libre de la fiche ; les notes datées sont `notes_log` (fiche détaillée).
json.notes plant.notes

json.placed plant.placed?
json.latitude plant.latitude
json.longitude plant.longitude
json.map_feature_id plant.map_feature_id

if plant.plant_species
  json.species do
    json.id plant.plant_species.id
    json.name plant.plant_species.name
    json.latin_name plant.plant_species.latin_name
  end
else
  json.species nil
end
if plant.plant_variety
  json.variety do
    json.id plant.plant_variety.id
    json.name plant.plant_variety.name
    json.plant_species_id plant.plant_variety.plant_species_id
  end
else
  json.variety nil
end

json.harvest_windows plant.harvest_windows do |window|
  json.partial! "api/v1/plant_harvest_windows/window", window: window
end
json.harvest_windows_inherited plant.harvest_windows_inherited?
json.harvest_windows_effective plant.harvest_windows_effective do |window|
  json.partial! "api/v1/plant_harvest_windows/window", window: window
  json.inherited window.owner_type == "PlantSpecies"
end

json.created_at plant.created_at
json.updated_at plant.updated_at
