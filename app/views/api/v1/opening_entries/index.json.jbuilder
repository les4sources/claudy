json.data @journal_entries do |journal_entry|
  json.partial! "api/v1/opening_entries/journal_entry", journal_entry: journal_entry
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @journal_entries }
