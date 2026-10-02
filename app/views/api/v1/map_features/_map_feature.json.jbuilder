json.id map_feature.id
json.type "map_feature"
json.feature_kind map_feature.feature_kind
json.layer_id map_feature.map_layer_id
json.layer_kind map_feature.map_layer&.kind
json.name map_feature.display_name
json.name_i18n map_feature.name_i18n
json.description_i18n map_feature.description_i18n
json.geometry map_feature.geometry
json.geometry_type map_feature.geometry_type
json.properties map_feature.properties
json.position map_feature.position
json.plant_id(map_feature.plant_point? ? map_feature.plant&.id : nil)
json.created_at map_feature.created_at
json.updated_at map_feature.updated_at
