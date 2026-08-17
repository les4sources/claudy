json.data @cash_entries do |cash_entry|
  json.partial! "api/v1/cash_entries/cash_entry", cash_entry: cash_entry
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @cash_entries }
