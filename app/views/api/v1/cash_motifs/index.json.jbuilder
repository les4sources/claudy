json.data @cash_motifs do |cash_motif|
  json.partial! "api/v1/cash_motifs/cash_motif", cash_motif: cash_motif
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @cash_motifs }
