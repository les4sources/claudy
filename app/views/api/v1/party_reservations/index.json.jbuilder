json.data @party_reservations do |party_reservation|
  json.partial! "api/v1/party_reservations/party_reservation", party_reservation: party_reservation
end
json.meta { json.partial! "api/v1/shared/pagination", paginated: @party_reservations }
