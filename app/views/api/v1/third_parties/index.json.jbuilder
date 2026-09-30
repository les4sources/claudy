json.data @third_parties do |third_party|
  json.partial! "api/v1/third_parties/third_party", third_party: third_party
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @third_parties }
