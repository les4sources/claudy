json.data do
  json.partial! "api/v1/paper_sheets/paper_sheet", paper_sheet: @paper_sheet
  json.totals_by_account(@totals || []) do |line|
    json.member_account_id line[:account]&.id
    json.name line[:account]&.name
    json.code line[:account]&.code
    json.entries line[:entries]
    json.cents line[:cents]
    json.formatted Money.new(line[:cents]).format
  end
end
json.meta do
  json.created @created unless @created.nil?
  if @report
    json.encoding do
      json.created @report.created
      json.updated @report.updated
      json.deleted @report.deleted
      json.locked @report.locked
      json.ignored @report.ignored
      json.summary @report.summary
    end
  end
end
