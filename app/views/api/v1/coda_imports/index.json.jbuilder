json.data @coda_imports do |coda_import|
  json.partial! "api/v1/coda_imports/coda_import", coda_import: coda_import
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @coda_imports }
