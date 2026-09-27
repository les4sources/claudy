json.data do
  json.partial! "api/v1/plants/plant", plant: @plant
  json.notes_log @plant.notes do |note|
    json.partial! "api/v1/map_notes/map_note", map_note: note
  end
  json.photos @plant.photos do |photo|
    json.partial! "api/v1/map_photos/photo", photo: photo
  end
  json.tasks @plant.map_tasks.sort_by { |task| [task.position.to_i, task.id] } do |task|
    json.partial! "api/v1/map_tasks/map_task", map_task: task
  end
end
json.meta { json.created @created } unless @created.nil?
