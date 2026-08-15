json.id coda_import.id
json.type "coda_import"
json.filename coda_import.filename
json.sha256 coda_import.sha256
json.creation_date coda_import.creation_date
json.file_reference coda_import.file_reference
json.status coda_import.status
json.statements_count coda_import.statements_count
json.entries_count coda_import.entries_count
json.imported_at coda_import.imported_at
json.statements coda_import.coda_statements do |statement|
  json.sequence_number statement.sequence_number
  json.cash_account_name statement.cash_account.name
  json.old_balance_on statement.old_balance_date
  json.new_balance_on statement.new_balance_date
  json.old_balance_cents statement.old_balance_cents
  json.new_balance_cents statement.new_balance_cents
  json.entries_count statement.entries_count
end
