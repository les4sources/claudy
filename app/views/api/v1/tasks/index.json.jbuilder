json.data @tasks do |task|
  json.partial! "api/v1/tasks/task", task: task
end
json.meta { json.partial! "api/v1/shared/pagination", collection: @tasks }
