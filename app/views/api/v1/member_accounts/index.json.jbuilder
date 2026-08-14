json.data @member_accounts do |member_account|
  json.partial! "api/v1/member_accounts/member_account", member_account: member_account
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @member_accounts }
