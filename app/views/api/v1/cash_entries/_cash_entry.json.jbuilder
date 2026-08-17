json.id cash_entry.id
json.type "cash_entry"
json.cash_account_id cash_entry.cash_account_id
json.cash_account_name cash_entry.cash_account.name
json.entry_date cash_entry.entry_date
json.value_date cash_entry.value_date
json.amount { json.partial! "api/v1/shared/money", money: cash_entry.amount }
json.label cash_entry.label
json.counterparty_name cash_entry.counterparty_name
json.communication cash_entry.communication
json.external_ref cash_entry.external_ref
json.statement_ref cash_entry.statement_ref
json.status cash_entry.status
json.status_label cash_entry.status_label
json.allocated_cents cash_entry.allocated_cents
json.posted cash_entry.posted?
json.url api_v1_cash_entry_url(cash_entry)
