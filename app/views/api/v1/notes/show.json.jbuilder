json.data { json.partial! "api/v1/notes/note", note: @note }
json.meta { json.created @created } unless @created.nil?
