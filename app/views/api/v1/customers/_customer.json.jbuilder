json.id customer.id
json.type "customer"
json.customer_type customer.customer_type
json.first_name customer.first_name
json.last_name customer.last_name
json.organization_name customer.organization_name
json.name customer.name
json.email customer.email
json.phone customer.phone
json.language customer.language
json.vat_number customer.vat_number
json.peppol_id customer.peppol_id
json.address do
  json.line customer.address_line
  json.zip customer.address_zip
  json.city customer.address_city
  json.country customer.address_country
end
json.marketing_consent customer.marketing_consent
json.nps_eligible customer.nps_eligible
json.stripe_customer_id customer.stripe_customer_id
json.human { json.partial! "api/v1/shared/ref", record: customer.human } if customer.human
json.created_at customer.created_at
json.updated_at customer.updated_at
json.url api_v1_customer_url(customer)

if detailed
  json.stays customer.stays do |stay|
    json.partial! "api/v1/stays/stay", stay: stay, detailed: false
  end
end
# NOTE: `notes` is internal-only (Pôle Accueil + collectif), never exposed via
# the API (decision §11.7 / AC). Do not add it here.
