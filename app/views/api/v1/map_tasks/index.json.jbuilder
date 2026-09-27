json.data @map_tasks do |map_task|
  json.partial! "api/v1/map_tasks/map_task", map_task: map_task
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @map_tasks }
