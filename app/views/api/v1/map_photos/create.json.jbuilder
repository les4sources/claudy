json.photos @photos do |photo|
  json.partial! "api/v1/map_photos/photo", photo: photo
end
