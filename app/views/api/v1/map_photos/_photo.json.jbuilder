json.id photo.id
json.filename photo.filename.to_s
json.content_type photo.blob.content_type
json.byte_size photo.blob.byte_size
json.url rails_blob_url(photo)
json.created_at photo.created_at
