json.id cycle_action.id
json.type "cycle_action"
json.label cycle_action.label
# `hours` est l'ESTIMÉ engagé ; `actual_hours` le réel (epic #330, phase 2).
# Le réel est en LECTURE seule : il ne bouge que par add/remove_actual_hour.
json.hours cycle_action.hours
json.actual_hours cycle_action.actual_hours
json.category cycle_action.category
json.completed cycle_action.completed
# Activité économique (epic #330, phase 1) — exposée en LECTURE seule.
json.economic cycle_action.economic
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
json.cycle_id cycle_action.cycle_id
json.outcome cycle_action.outcome
json.deferred_from_id cycle_action.deferred_from_id
json.deferral_count cycle_action.deferral_count
# Copie au cycle suivant (epic #330, phase 4) — exposée en LECTURE seule.
json.copied_from_id cycle_action.copied_from_id
# Pôle de l'action (epic #330, phase 5) — exposé en LECTURE seule.
if cycle_action.team
  json.team { json.partial! "api/v1/shared/ref", record: cycle_action.team }
else
  json.team nil
end
