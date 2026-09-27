json.data @plant_species_list do |plant_species|
  json.partial! "api/v1/plant_species/plant_species", plant_species: plant_species
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @plant_species_list }
