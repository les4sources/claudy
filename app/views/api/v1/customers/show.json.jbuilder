json.data do
  json.partial! "api/v1/customers/customer", customer: @customer, detailed: true
end
