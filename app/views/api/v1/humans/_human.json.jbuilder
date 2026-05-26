json.id human.id
json.type "human"
json.name human.name
json.email human.email
json.summary human.summary
json.description human.description.respond_to?(:to_plain_text) ? human.description.to_plain_text : human.description
json.status human.status
json.photo_url(human.photo.present? ? human.photo.url : nil)
json.created_at human.created_at
json.updated_at human.updated_at
json.url api_v1_human_url(human)
