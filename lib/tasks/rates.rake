namespace :rates do
  desc "Matérialise tous les tarifs de Pricing::Catalog dans la table rates (idempotent). FORCE=1 pour écraser les montants édités."
  task seed_from_catalog: :environment do
    result = Rates::SeedFromCatalog.new(force: ENV["FORCE"].present?).run
    puts "[rates:seed_from_catalog] #{result}"
  end
end
