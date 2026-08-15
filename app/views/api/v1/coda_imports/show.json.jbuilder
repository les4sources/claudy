if @coda_import
  json.data { json.partial! "api/v1/coda_imports/coda_import", coda_import: @coda_import }
else
  json.data nil
end
if @report
  json.meta do
    json.status @report.status
    json.statements @report.statements
    json.entries_created @report.entries_created
    json.statements_skipped @report.statements_skipped
    json.messages @report.messages
  end
end
