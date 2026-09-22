json.data @allocation_rules do |allocation_rule|
  json.partial! "api/v1/allocation_rules/allocation_rule", allocation_rule: allocation_rule
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @allocation_rules }
