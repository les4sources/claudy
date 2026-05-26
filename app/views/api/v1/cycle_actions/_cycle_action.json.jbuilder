json.id cycle_action.id
json.type "cycle_action"
json.label cycle_action.label
json.hours cycle_action.hours
json.category cycle_action.category
json.completed cycle_action.completed
json.position cycle_action.position
json.archived cycle_action.archived?
json.archived_at cycle_action.archived_at
json.human { json.partial! "api/v1/shared/ref", record: cycle_action.human }
if cycle_action.delegate_to_human
  json.delegate_to_human { json.partial! "api/v1/shared/ref", record: cycle_action.delegate_to_human }
else
  json.delegate_to_human nil
end
json.created_at cycle_action.created_at
json.updated_at cycle_action.updated_at
json.url api_v1_cycle_action_url(cycle_action)
