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

  desc "Réaligne les tarifs des salles sur la page tarifs du site (epic #234). Dry-run par défaut, APPLY=1 pour écrire."
  task align_halls_with_website: :environment do
    apply  = ENV["APPLY"].present?
    result = Rates::AlignHallsWithWebsite.new(dry_run: !apply).run

    puts "[rates:align_halls_with_website] #{result}"
    { "créées" => result.created, "réalignées" => result.realigned,
      "conservées (éditées à la main)" => result.kept }.each do |title, rows|
      next if rows.empty?

      puts "  #{title} :"
      rows.each { |row| puts "    - #{row}" }
    end
    puts "[rates:align_halls_with_website] Rien n'a été écrit — relance avec APPLY=1." unless apply
  end

  desc "Crée les clés du barème « Sourciers » (bar, épicerie, repas, cagnotte, dôme, animaux). Idempotent, ne réécrit jamais un montant existant."
  task seed_sourciers: :environment do
    result = Rates::SeedSourciers.new.run
    puts "[rates:seed_sourciers] #{result}"
  end
end
