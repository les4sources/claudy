namespace :finance do
  desc "Seed d'un catalogue de départ (bar + cellier) avec son premier palier — idempotent"
  task seed_catalog: :environment do
    # Les deux articles réels servent d'exemples vivants ET de garde-fou contre
    # l'inversion des deux règles de prix, qui vont en sens opposé :
    #   bar     : sourcier = achat × 1,10, très EN DESSOUS du prix public
    #   cellier : sourcier = référence × 0,95, public = référence × 1,05
    seeds = [
      { name: "Moinette", channel: "bar", category: "Bières", unit: "piece",
        purchase: 191, reference: nil, member: 210, public: 400 },
      { name: "Chimay bleue", channel: "bar", category: "Bières", unit: "piece",
        purchase: 210, reference: nil, member: 231, public: 420 },
      { name: "Jus de pomme", channel: "bar", category: "Sans alcool", unit: "piece",
        purchase: 120, reference: nil, member: 132, public: 250 },
      { name: "Avoine bio", channel: "grocery", category: "Vracs secs", unit: "kg",
        purchase: 240, reference: 295, member: 280, public: 310 },
      { name: "Lentilles vertes", channel: "grocery", category: "Vracs secs", unit: "kg",
        purchase: 320, reference: 390, member: 371, public: 410 },
      { name: "Huile d'olive", channel: "grocery", category: "Épicerie", unit: "l",
        purchase: 950, reference: 1150, member: 1093, public: 1208 }
    ]

    created_items = 0
    created_prices = 0

    seeds.each do |seed|
      item = CatalogItem.find_or_initialize_by(name: seed[:name], channel: seed[:channel])
      if item.new_record?
        item.assign_attributes(category: seed[:category], unit: seed[:unit])
        item.save!
        created_items += 1
      end

      # Un article déjà tarifé n'est jamais retarifé : le seed pose un point de
      # départ, il ne redresse pas un prix que quelqu'un a corrigé depuis.
      next if item.catalog_prices.exists?

      item.catalog_prices.create!(
        active_from: RateVersion::ORIGIN,
        purchase_price_cents: seed[:purchase],
        reference_price_cents: seed[:reference],
        member_price_cents: seed[:member],
        public_price_cents: seed[:public],
        note: "Palier initial (seed #157)"
      )
      created_prices += 1
    end

    puts "[finance:seed_catalog] #{created_items} article(s) créé(s), " \
         "#{created_prices} palier(s) initial(aux) créé(s), " \
         "#{CatalogItem.count} article(s) au catalogue"
  end

  desc "Génère les charges récurrentes d'un mois — MONTH=2026-08, dry-run par défaut, APPLY=1 pour écrire"
  task generate_recurring: :environment do
    month = ENV["MONTH"].presence || Date.current.strftime("%Y-%m")
    apply = ENV["APPLY"] == "1"

    report = Finance::GenerateRecurringCharges.new(month: month, dry_run: !apply).run!

    report.created.each do |line|
      puts "  + #{line[:charge].member_account.name.ljust(28)} #{line[:label].ljust(34)} " \
           "#{format('%8.2f', line[:amount_cents] / 100.0)} €"
    end
    report.skipped.each do |line|
      puts "  ! #{line[:charge].label} — #{line[:reason]}"
    end

    puts "[finance:generate_recurring] #{month} : #{report.created.size} à créer, " \
         "#{report.existing.size} déjà présente(s), #{report.skipped.size} ignorée(s), " \
         "total #{format('%.2f', report.total_cents / 100.0)} €"
    puts "[finance:generate_recurring] Rien n'a été écrit — relance avec APPLY=1." unless apply
  end
end
