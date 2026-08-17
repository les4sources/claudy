json.id journal_entry.id
json.type "journal_entry"
json.journal journal_entry.journal
json.number journal_entry.number
json.fiscal_year_id journal_entry.fiscal_year_id
json.legal_entity_id journal_entry.legal_entity_id
json.entry_date journal_entry.entry_date
json.label journal_entry.label
json.reversal_of_id journal_entry.reversal_of_id
json.debit_cents journal_entry.journal_lines.sum(&:debit_cents)
json.credit_cents journal_entry.journal_lines.sum(&:credit_cents)
json.lines journal_entry.journal_lines do |line|
  json.general_account_code line.general_account.code
  json.general_account_name line.general_account.name
  json.analytic_account_code line.analytic_account&.code
  json.debit_cents line.debit_cents
  json.credit_cents line.credit_cents
  json.label line.label
end
