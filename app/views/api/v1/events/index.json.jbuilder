json.data @events do |event|
  json.partial! "api/v1/events/event", event: event
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @events }
