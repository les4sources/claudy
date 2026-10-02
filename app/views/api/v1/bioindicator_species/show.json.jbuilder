json.data { json.partial! "api/v1/bioindicator_species/bioindicator_species", bioindicator_species: @bioindicator_species }
json.meta { json.created @created } unless @created.nil?
