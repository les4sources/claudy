json.data @humans do |human|
  json.partial! "api/v1/humans/human", human: human
end
json.meta { json.partial! "api/v1/shared/pagination", collection: @humans }
