json.data @paper_sheets do |paper_sheet|
  json.partial! "api/v1/paper_sheets/paper_sheet", paper_sheet: paper_sheet
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @paper_sheets }
