json.data { json.partial! "api/v1/compliance_obligations/compliance_obligation", compliance_obligation: @compliance_obligation }
json.meta { json.created @created } unless @created.nil?
