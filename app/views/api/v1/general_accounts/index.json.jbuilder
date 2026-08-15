json.data @general_accounts do |general_account|
  json.partial! "api/v1/general_accounts/general_account", general_account: general_account
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @general_accounts }
