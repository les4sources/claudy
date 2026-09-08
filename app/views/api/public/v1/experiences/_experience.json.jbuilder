# Forme du contrat `docs/CLAUDY.md` du site. Champs vides omis. Le porteur
# n'est désigné que par son prénom — aucune donnée personnelle ne sort d'ici.
json.ignore_nil!

json.id experience.id
json.slug experience.slug
json.name experience.name
json.summary experience.summary.presence
json.description_html public_html(experience.description)
json.duration_text experience.public_duration_text
json.duration_minutes experience.block_duration_minutes
if experience.price_cents
  json.price do
    json.amount_cents experience.price_cents
    json.currency "EUR"
    json.per "participant"
  end
end
json.fixed_price do
  json.amount_cents experience.fixed_price_cents.to_i
  json.currency "EUR"
end
json.min_participants experience.min_participants
json.max_participants experience.max_participants
if experience.human
  json.carrier do
    json.name experience.human.name.to_s.split.first
  end
end
if experience.photo?
  json.image do
    json.partial! "api/public/v1/experiences/photo", experience: experience
  end
end
json.availabilities availabilities do |availability|
  json.date availability.available_on.iso8601
  json.starts_at availability.starts_at
  json.ends_at availability.ends_at
  json.spots_left availability.available_spots
end
json.booking_url absolute_url("/reservation")
json.published_at experience.published_at&.iso8601
json.updated_at experience.updated_at.iso8601
json.path experience.public_path
