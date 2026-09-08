# Photo CarrierWave (fichier original) en URL absolue ; dimensions lues sur le
# disque quand c'est possible, omises sinon (le site les recalcule au build).
json.ignore_nil!

json.url absolute_url(experience.photo.url)
json.alt experience.name
dimensions = experience.photo_dimensions
if dimensions
  json.width dimensions[0]
  json.height dimensions[1]
end
