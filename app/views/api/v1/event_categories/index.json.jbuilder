json.data @event_categories do |event_category|
  json.partial! "api/v1/event_categories/event_category", event_category: event_category
end
