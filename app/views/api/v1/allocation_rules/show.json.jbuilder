json.data { json.partial! "api/v1/allocation_rules/allocation_rule", allocation_rule: @allocation_rule }
json.meta { json.created @created } unless @created.nil?
