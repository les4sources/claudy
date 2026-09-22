json.id allocation_rule.id
json.type "allocation_rule"
json.label allocation_rule.label
json.position allocation_rule.position
json.confidence allocation_rule.confidence
json.active allocation_rule.active
json.direction allocation_rule.direction
json.direction_label allocation_rule.direction_label

json.criteria do
  json.counterparty_iban allocation_rule.counterparty_iban
  json.counterparty_name_contains allocation_rule.counterparty_name_contains
  json.communication_contains allocation_rule.communication_contains
  json.transaction_code allocation_rule.transaction_code
  json.min_amount_cents allocation_rule.min_amount_cents
  json.max_amount_cents allocation_rule.max_amount_cents
end

json.general_account_code allocation_rule.general_account&.code
json.general_account_name allocation_rule.general_account&.name
json.analytic_account_code allocation_rule.analytic_account&.code
json.team_name allocation_rule.team&.name
json.legal_entity_name allocation_rule.legal_entity&.name
json.event_id allocation_rule.event_id

json.accepted_count allocation_rule.accepted_count
json.rejected_count allocation_rule.rejected_count
json.url api_v1_allocation_rule_url(allocation_rule)
