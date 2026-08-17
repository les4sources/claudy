json.data @account_settlements do |account_settlement|
  json.partial! "api/v1/account_settlements/account_settlement", account_settlement: account_settlement
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @account_settlements }
