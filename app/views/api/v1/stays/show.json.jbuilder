json.data do
  json.partial! "api/v1/stays/stay", stay: @stay, detailed: true
end
