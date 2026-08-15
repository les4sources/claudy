json.data { json.partial! "api/v1/general_accounts/general_account", general_account: @general_account }
json.meta { json.created @created } unless @created.nil?
