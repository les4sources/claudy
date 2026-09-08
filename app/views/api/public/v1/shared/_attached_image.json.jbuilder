# Image ActiveStorage : URL absolue stable (redirection signée permanente vers
# le fichier), dimensions quand l'analyse a eu lieu.
json.ignore_nil!

blob = attachment.blob
json.url absolute_url(rails_blob_path(attachment, only_path: true))
json.alt alt
json.width blob.metadata["width"]
json.height blob.metadata["height"]
