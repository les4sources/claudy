json.data { json.partial! "api/v1/event_categories/event_category", event_category: @event_category }
json.meta { json.created @created } unless @created.nil?
