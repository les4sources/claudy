json.data @map_features do |map_feature|
  json.partial! "api/v1/map_features/map_feature", map_feature: map_feature
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @map_features }
