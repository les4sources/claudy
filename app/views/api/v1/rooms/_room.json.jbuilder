json.id room.id
json.type "room"
json.name room.name
json.name_with_level room.name_with_level
json.description room.description
json.level room.level
json.code room.code
json.lodgings room.lodgings do |lodging|
  json.partial! "api/v1/shared/ref", record: lodging
end
json.created_at room.created_at
json.updated_at room.updated_at
json.url api_v1_room_url(room)
