json.id event.id
json.type "event"
json.name event.name
json.slug event.slug
json.summary event.summary
json.starts_at event.starts_at&.iso8601
json.ends_at event.ends_at&.iso8601
json.all_day event.all_day?
json.location event.location
json.price_text event.price_text
# Lien d'inscription (billetterie, formulaire) : la colonne `url` du modèle,
# nommée comme dans l'API publique. `url` reste, comme partout dans cette API,
# l'adresse de la ressource elle-même.
json.registration_url event.url
json.status event.status
json.public_description event.public_description.to_s.presence
json.event_category_id event.event_category_id
if event.event_category
  json.category do
    json.slug event.event_category.slug
    json.name event.event_category.name
    json.pole event.event_category.pole
  end
end
json.team_id event.team_id
json.published event.published?
json.published_at event.published_at&.iso8601
json.public_url event.public_url
json.image_url(event.image.attached? ? rails_blob_url(event.image) : nil)
json.created_at event.created_at
json.updated_at event.updated_at
json.url api_v1_event_url(event)
