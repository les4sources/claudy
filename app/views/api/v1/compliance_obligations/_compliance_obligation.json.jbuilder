json.id compliance_obligation.id
json.type "compliance_obligation"
json.title compliance_obligation.title
json.legal_entity_name compliance_obligation.legal_entity.name
json.frequency compliance_obligation.frequency
json.first_due_on compliance_obligation.first_due_on
json.ends_on compliance_obligation.ends_on
json.covers compliance_obligation.covers
json.payment compliance_obligation.payment
json.responsible_email compliance_obligation.responsible_user&.email
json.instructions compliance_obligation.instructions
json.active compliance_obligation.active
json.deadlines compliance_obligation.compliance_deadlines.ordered do |deadline|
  json.partial! "api/v1/compliance_deadlines/compliance_deadline", compliance_deadline: deadline
end
json.url api_v1_compliance_obligation_url(compliance_obligation)
