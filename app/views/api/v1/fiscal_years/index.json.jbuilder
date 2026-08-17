json.data @fiscal_years do |fiscal_year|
  json.partial! "api/v1/fiscal_years/fiscal_year", fiscal_year: fiscal_year
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @fiscal_years }
