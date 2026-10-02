json.data do
  json.partial! "api/v1/map_features/map_feature", map_feature: @map_feature
  json.notes_log @map_feature.map_notes do |note|
    json.partial! "api/v1/map_notes/map_note", map_note: note
  end
  json.photos @map_feature.photos do |photo|
    json.partial! "api/v1/map_photos/photo", photo: photo
  end
  json.tasks @map_feature.map_tasks.sort_by { |task| [task.position.to_i, task.id] } do |task|
    json.partial! "api/v1/map_tasks/map_task", map_task: task
  end
end
