json.id human_role.id
json.type "human_role"
json.date human_role.date
json.status human_role.status
json.human { json.partial! "api/v1/shared/ref", record: human_role.human }
json.role { json.partial! "api/v1/shared/ref", record: human_role.role }
json.has_watchman_note human_role.has_watchman_note?
json.created_at human_role.created_at
json.updated_at human_role.updated_at
json.url api_v1_human_role_url(human_role)
