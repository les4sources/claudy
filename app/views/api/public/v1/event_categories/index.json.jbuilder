json.generated_at Time.current.utc.iso8601
json.categories @categories do |category|
  json.partial! "api/public/v1/event_categories/category", category: category
end
