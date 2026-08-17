json.data @cash_accounts do |cash_account|
  json.partial! "api/v1/cash_accounts/cash_account", cash_account: cash_account
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @cash_accounts }
