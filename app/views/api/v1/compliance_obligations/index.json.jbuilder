json.data @compliance_obligations do |compliance_obligation|
  json.partial! "api/v1/compliance_obligations/compliance_obligation", compliance_obligation: compliance_obligation
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @compliance_obligations }
