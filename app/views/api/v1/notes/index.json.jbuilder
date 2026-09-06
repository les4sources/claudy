json.data @notes do |note|
  json.partial! "api/v1/notes/note", note: note
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @notes }
