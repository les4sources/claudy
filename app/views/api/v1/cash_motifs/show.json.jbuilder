json.data { json.partial! "api/v1/cash_motifs/cash_motif", cash_motif: @cash_motif }
json.meta { json.created @created } unless @created.nil?
