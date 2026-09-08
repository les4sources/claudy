# Forme du contrat `docs/CLAUDY.md` du site. Les champs vides sont OMIS (pas
# `null`) : le schéma Zod du site les déclare optionnels.
json.ignore_nil!

json.id event.id
json.slug event.slug
json.title event.name
json.summary event.summary.presence
json.description_html public_html(event.public_description)
json.starts_at event.starts_at&.iso8601
json.ends_at event.ends_at&.iso8601
json.all_day event.all_day?
if event.event_category
  json.category do
    json.partial! "api/public/v1/event_categories/category", category: event.event_category
  end
end
json.location event.location.presence
json.price_text event.price_text.presence
json.registration_url event.url.presence
if event.image.attached?
  json.image do
    json.partial! "api/public/v1/shared/attached_image", attachment: event.image, alt: event.name
  end
end
json.published_at event.published_at&.iso8601
json.updated_at event.updated_at.iso8601
json.path event.public_path
