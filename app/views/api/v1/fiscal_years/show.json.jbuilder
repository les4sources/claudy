json.data { json.partial! "api/v1/fiscal_years/fiscal_year", fiscal_year: @fiscal_year }
json.meta { json.created @created } unless @created.nil?
