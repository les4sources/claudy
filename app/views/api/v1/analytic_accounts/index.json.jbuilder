json.data @analytic_accounts do |analytic_account|
  json.partial! "api/v1/analytic_accounts/analytic_account", analytic_account: analytic_account
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @analytic_accounts }
