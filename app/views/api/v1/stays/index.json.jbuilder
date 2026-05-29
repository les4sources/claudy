json.data @stays do |stay|
  json.partial! "api/v1/stays/stay", stay: stay, detailed: false
end
json.meta { json.partial! "api/v1/shared/pagination", collection: @stays }
