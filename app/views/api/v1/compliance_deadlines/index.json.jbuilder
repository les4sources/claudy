json.data @compliance_deadlines do |compliance_deadline|
  json.partial! "api/v1/compliance_deadlines/compliance_deadline", compliance_deadline: compliance_deadline
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @compliance_deadlines }
