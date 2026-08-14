json.id member_account.id
json.type "member_account"
json.code member_account.code
json.name member_account.name
json.kind member_account.kind
json.kind_label member_account.kind_label
json.active member_account.active
json.household_id member_account.household_id
json.human_id member_account.human_id
json.contact_email member_account.contact_email
json.opening_balance { json.partial! "api/v1/shared/money", money: member_account.opening_balance }
json.balance_cents member_account.balance_cents
json.balance_formatted Money.new(member_account.balance_cents).format
json.entries_count member_account.entries_count
json.last_entry_on member_account.last_entry_on
json.created_at member_account.created_at
json.updated_at member_account.updated_at
json.url api_v1_member_account_url(member_account)
