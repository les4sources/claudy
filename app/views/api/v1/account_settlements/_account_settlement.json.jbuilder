json.id account_settlement.id
json.type "account_settlement"
json.member_account_id account_settlement.member_account_id
json.amount { json.partial! "api/v1/shared/money", money: account_settlement.amount }
json.received_on account_settlement.received_on
# `method` est un message d'Object : `json.method "x"` appellerait Object#method
# au lieu de poser une clé. On passe donc par `set!`.
json.set! "method", account_settlement[:method]
json.method_label account_settlement.method_label
json.received_channel account_settlement.received_channel
json.channel_label account_settlement.channel_label
json.reference account_settlement.reference
json.bank_reference account_settlement.bank_reference
json.notes account_settlement.notes
json.account_entry_id account_settlement.account_entry_id
json.created_at account_settlement.created_at
json.updated_at account_settlement.updated_at
