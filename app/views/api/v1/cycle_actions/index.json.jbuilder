json.data @cycle_actions do |cycle_action|
  json.partial! "api/v1/cycle_actions/cycle_action", cycle_action: cycle_action
end
json.meta { json.partial! "api/v1/shared/pagination", collection: @cycle_actions }
