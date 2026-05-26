json.data @rooms do |room|
  json.partial! "api/v1/rooms/room", room: room
end
json.meta { json.partial! "api/v1/shared/pagination", collection: @rooms }
