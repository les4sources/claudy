json.data { json.partial! "api/v1/analytic_accounts/analytic_account", analytic_account: @analytic_account }
json.meta { json.created @created } unless @created.nil?
