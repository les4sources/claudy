json.data @customers do |customer|
  json.partial! "api/v1/customers/customer", customer: customer, detailed: false
end
json.meta { json.partial! "api/v1/shared/pagination", collection: @customers }
