namespace :rates do
  desc "Matérialise tous les tarifs de Pricing::Catalog dans la table rates (idempotent). FORCE=1 pour écraser les montants édités."
  task seed_from_catalog: :environment do
    result = Rates::SeedFromCatalog.new(force: ENV["FORCE"].present?).run
    puts "[rates:seed_from_catalog] #{result}"
  end

  desc "Donne une version datée initiale à chaque tarif qui n'en a pas (issue #156). Dry-run par défaut, APPLY=1 pour écrire."
  task backfill_versions: :environment do
    apply = ENV["APPLY"].present?
    result = Rates::BackfillVersions.new(dry_run: !apply).run
    puts "[rates:backfill_versions] #{result}"
    puts "[rates:backfill_versions] Rien n'a été écrit — relance avec APPLY=1." unless apply
  end

  desc "Crée les clés du barème « Sourciers » (bar, épicerie, repas, cagnotte, dôme, animaux). Idempotent, ne réécrit jamais un montant existant."
  task seed_sourciers: :environment do
    result = Rates::SeedSourciers.new.run
    puts "[rates:seed_sourciers] #{result}"
  end
end
