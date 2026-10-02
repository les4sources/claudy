json.data { json.partial! "api/v1/events/event", event: @event }
json.meta { json.created @created } unless @created.nil?
