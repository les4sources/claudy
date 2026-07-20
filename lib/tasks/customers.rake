# Fourre-tout par OTA (2026-07-20) : crée (idempotent) les clients « Client
# Airbnb » et « Client Booking.com » — les réservations OTA sans email s'y
# rattachent au lieu d'engorger le fourre-tout générique. À lancer une fois
# en prod : `rake customers:ensure_ota_catch_alls`.
namespace :customers do
  desc "Crée les clients fourre-tout par OTA (idempotent)"
  task ensure_ota_catch_alls: :environment do
    labels = { "airbnb" => "Airbnb", "bookingdotcom" => "Booking.com" }
    Customer::OTA_CATCH_ALL_EMAILS.each do |platform, email|
      customer = Customer.where(email: email).first_or_initialize
      created = customer.new_record?
      customer.first_name ||= "Client"
      customer.last_name  ||= labels.fetch(platform, platform)
      customer.customer_type ||= "organization"
      customer.organization_name ||= labels.fetch(platform, platform)
      customer.save!
      puts "#{created ? "créé" : "déjà présent"} : #{customer.first_name} #{customer.last_name} <#{email}> (##{customer.id})"
    end
  end
end
