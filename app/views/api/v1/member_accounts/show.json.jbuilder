json.data { json.partial! "api/v1/member_accounts/member_account", member_account: @member_account }
json.meta { json.created @created } unless @created.nil?
