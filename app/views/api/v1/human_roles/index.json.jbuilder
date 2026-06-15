json.data @human_roles do |human_role|
  json.partial! "api/v1/human_roles/human_role", human_role: human_role
end
json.meta { json.partial! "api/v1/shared/pagination", collection: @human_roles }
