json.generated_at Time.current.utc.iso8601
json.events @events do |event|
  json.partial! "api/public/v1/events/event", event: event
end
