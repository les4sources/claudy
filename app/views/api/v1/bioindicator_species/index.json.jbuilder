json.data @bioindicator_species_list do |bioindicator_species|
  json.partial! "api/v1/bioindicator_species/bioindicator_species", bioindicator_species: bioindicator_species
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @bioindicator_species_list }
