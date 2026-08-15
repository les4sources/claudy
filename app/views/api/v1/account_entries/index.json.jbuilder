json.data @account_entries do |account_entry|
  json.partial! "api/v1/account_entries/account_entry", account_entry: account_entry
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @account_entries }
