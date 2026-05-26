json.id task.id
json.type "task"
json.name task.name
json.description task.description.respond_to?(:to_plain_text) ? task.description.to_plain_text : task.description
json.status task.status
json.due_date task.due_date
json.project_id task.project_id
json.team_id task.team_id
json.bundle_id task.bundle_id
json.humans task.humans do |human|
  json.partial! "api/v1/shared/ref", record: human
end
json.created_at task.created_at
json.updated_at task.updated_at
json.url api_v1_task_url(task)
