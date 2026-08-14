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

  desc "Seed des marges sourcier par canal (bar / cellier / repas) — idempotent"
  task seed_margins: :environment do
    # Une seule notion : le prix sourcier = prix d'achat + marge. Les valeurs
    # de départ reproduisent au plus près ce qui se pratiquait :
    #   bar     10 % — exactement l'ancien « achat × 1,10 »
    #   cellier 17 % — l'avoine passait de 2,40 € d'achat à 2,80 € sourcier
    #   repas    0 % — pas de marge sur un repas, son prix est un barème
    marges = {
      "catalog.margin.bar" => [10, "Marge sourcier — Bar (%)"],
      "catalog.margin.grocery" => [17, "Marge sourcier — Cellier (%)"],
      "catalog.margin.meal" => [0, "Marge sourcier — Repas (%)"]
    }

    creees = 0
    marges.each do |key, (percent, label)|
      rate = Rate.find_or_initialize_by(key: key)
      next unless rate.new_record?

      rate.update!(amount_cents: percent, unit: "percent", label: label)
      rate.rate_versions.create!(amount_cents: percent, active_from: RateVersion::ORIGIN,
                                 note: "Marge initiale")
      creees += 1
    end

    # Les anciennes clés ne servent plus au prix sourcier. On ne les supprime
    # pas — elles restent dans l'historique des paliers déjà posés — mais leur
    # libellé le dit, pour que personne ne les édite en croyant agir.
    { "bar.member_markup" => "OBSOLÈTE — remplacée par « Marge sourcier — Bar »",
      "grocery.member_ratio" => "OBSOLÈTE — remplacée par « Marge sourcier — Cellier »" }.each do |key, label|
      rate = Rate.find_by(key: key)
      rate&.update!(label: label) unless rate&.label.to_s.start_with?("OBSOLÈTE")
    end

    puts "[finance:seed_margins] #{creees} marge(s) créée(s), #{marges.size - creees} déjà présente(s)."
    Rate.ordered.where("key LIKE 'catalog.margin.%'").each do |rate|
      puts "  #{rate.key.ljust(24)} #{rate.amount_cents} %"
    end
  end

  desc "Seed du forfait charges habitants — 65 €/personne à partir du 01/02/2026"
  task seed_housing_charges: :environment do
    rate = Rate.find_or_initialize_by(key: "charges.per_person_monthly")
    if rate.new_record?
      rate.update!(amount_cents: 6500, unit: "cents", label: "Charges habitants — €/personne/mois")
      # Pas de version AVANT le 01/02/2026 : les charges d'avant étaient d'un
      # autre montant, qu'on ne connaît pas. Générer un mois antérieur ne
      # résoudra donc rien et sera SIGNALÉ, plutôt que facturé au mauvais tarif.
      rate.rate_versions.create!(amount_cents: 6500, active_from: Date.new(2026, 2, 1),
                                 note: "Barème en vigueur depuis le 01/02/2026")
      puts "[finance:seed_housing_charges] barème créé : 65,00 €/personne à partir du 01/02/2026"
    else
      puts "[finance:seed_housing_charges] barème déjà présent : #{rate.amount_cents / 100.0} €"
    end

    # Un barème ne facture rien tout seul : il dit COMBIEN, la règle dit à QUI
    # et depuis quand. On pose donc aussi les deux règles standard, qui visent
    # tous les ménages habitants. Créer une règle ne débite personne — la
    # génération reste une action séparée, avec aperçu et confirmation.
    regles = [
      { label: "Charges habitants", basis: "per_person", flow: "charges",
        rate_key: "charges.per_person_monthly", starts_on: Date.new(2026, 2, 1) },
      { label: "Cagnotte habitants", basis: "per_adult", flow: "pot",
        rate_key: "pot.monthly_per_adult", split_rate_key: "pot.swing_share",
        split_label: "Balançoire — Magali", starts_on: Date.new(2026, 2, 1) }
    ]

    creees = 0
    regles.each do |attrs|
      next if RecurringCharge.unscoped.exists?(label: attrs[:label], applies_to: "resident_households")

      RecurringCharge.create!(attrs.merge(applies_to: "resident_households", active: true))
      creees += 1
    end

    puts "[finance:seed_housing_charges] #{creees} règle(s) créée(s), " \
         "#{regles.size - creees} déjà présente(s)"
    RecurringCharge.ordered.each do |charge|
      montant = charge.unit_amount_cents_on(Date.current)
      puts "  · #{charge.label.ljust(22)} #{charge.basis_label.ljust(30)} " \
           "#{montant ? format('%.2f €', montant / 100.0) : 'barème non résolu'} " \
           "· #{charge.scope_label} (#{charge.target_accounts.size} compte(s))"
    end
    puts "[finance:seed_housing_charges] Rien n'est facturé : passe par « Prévisualiser le mois » pour générer."
  end

  desc "Recalcule chaque solde depuis les écritures et le compare aux décomptes figés — exit 1 si écart"
  task verify_ledger: :environment do
    ecarts = []

    MemberAccount.unscoped.find_each do |account|
      statements = AccountStatement.unscoped
                                   .where(member_account_id: account.id)
                                   .order(:period_month).to_a
      next if statements.empty?

      # Contrôle 1 — chaque décompte doit refermer sa propre addition.
      statements.each do |statement|
        attendu = statement.opening_balance_cents + statement.debits_cents + statement.credits_cents
        next if attendu == statement.closing_balance_cents

        ecarts << "#{account.code} #{statement.period_month.strftime('%Y-%m')} : clôture figée " \
                  "#{statement.closing_balance_cents}, recalculée #{attendu}"
      end

      # Contrôle 2 — le CHAÎNAGE : l'ouverture d'un mois est la clôture du
      # précédent. C'est lui qui attrape une écriture glissée entre deux
      # décomptes déjà émis.
      statements.each_cons(2) do |precedent, suivant|
        next if suivant.opening_balance_cents == precedent.closing_balance_cents

        ecarts << "#{account.code} #{suivant.period_month.strftime('%Y-%m')} : ouverture " \
                  "#{suivant.opening_balance_cents} ≠ clôture précédente #{precedent.closing_balance_cents}"
      end

      # Contrôle 3 — le solde du compte doit égaler la clôture du dernier
      # décompte plus les écritures non encore couvertes.
      dernier = statements.last
      hors_decompte = AccountEntry.unscoped
                                  .where(member_account_id: account.id, account_statement_id: nil)
                                  .where("entry_date > ?", dernier.period_month.end_of_month)
                                  .sum(:amount_cents)
      attendu = dernier.closing_balance_cents + hors_decompte
      next if attendu == account.balance_cents

      ecarts << "#{account.code} : solde courant #{account.balance_cents}, attendu #{attendu}"
    end

    if ecarts.empty?
      puts "[finance:verify_ledger] Aucun écart — #{AccountStatement.unscoped.count} décompte(s) vérifié(s)."
    else
      puts "[finance:verify_ledger] #{ecarts.size} écart(s) :"
      ecarts.each { |e| puts "  ! #{e}" }
      exit 1
    end
  end

  desc "Génère les charges récurrentes d'un mois — MONTH=2026-08, dry-run par défaut, APPLY=1 pour écrire"
  task generate_recurring: :environment do
    month = ENV["MONTH"].presence || Date.current.strftime("%Y-%m")
    apply = ENV["APPLY"] == "1"

    report = Finance::GenerateRecurringCharges.new(month: month, dry_run: !apply).run!

    report.created.each do |line|
      nom = (line[:account] || line[:charge].member_account)&.name.to_s
      puts "  + #{nom.ljust(28)} #{line[:label].ljust(34)} " \
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
