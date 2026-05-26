json.data @payments do |payment|
  json.partial! "api/v1/payments/payment", payment: payment
end
json.meta { json.partial! "api/v1/shared/pagination", collection: @payments }
