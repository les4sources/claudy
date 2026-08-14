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

  # ---------------------------------------------------------------------------
  # Reprise du bar papier — juillet 2026
  #
  # Le catalogue du bar n'existait nulle part ailleurs que sur la feuille A4
  # scotchée au mur. Ces deux tâches le font entrer dans l'app, puis encodent la
  # fiche de juillet 2026 relevée dessus. Elles sont IDEMPOTENTES et rejouables :
  # c'est ce qui permet de répéter en dry-run avant d'écrire en prod.
  #
  # Sources : « Fiche de BAR — juillet 2026 » (colonne +10 % = prix sourcier,
  # bâtonnets par famille) et « Au bar des 4 Sources » (carte août 2026, prix
  # publics). Comptages relus deux fois et arbitrés avec Michael le 14/08/2026.
  # ---------------------------------------------------------------------------

  BAR_2026_07 = Date.new(2026, 7, 1)

  # [nom, catégorie, unité, sourcier, achat, public] — montants en cents.
  #
  # Le prix d'achat vaut sourcier ÷ 1,10 (marge bar) SAUF là où il est nil : ces
  # articles-là ne s'achètent pas à l'unité, leur prix sourcier est une décision
  # maison (bouteille de vin, repas, miel, pizza party) ou une portion tirée du
  # vrac (tisane, sirop, café, jus au verre). On n'invente pas un prix fournisseur.
  BAR_CATALOG_2026_07 = [
    ["Moinette",                 "Bières", "piece", 210, 191, 400],
    ["Lupulus fruit",            "Bières", "piece", 205, 186, 400],
    ["Ducassis",                 "Bières", "piece", 193, 175, 400],
    ["Seed",                     "Bières", "piece", 189, 172, 400],
    ["Holy IPA",                 "Bières", "piece", 198, 180, 400],
    ["Acid",                     "Bières", "piece", 198, 180, 400],
    ["Big Nose",                 "Bières", "piece", 196, 178, 400],
    ["Cambrée",                  "Bières", "piece", 195, 177, 350],
    ["Topless",                  "Bières", "piece", 180, 164, 300],
    ["Chinette",                 "Bières", "piece", 195, 177, 350],
    ["Chimay dorée",             "Bières", "piece", 146, 133, nil],
    ["Lupulus organicus",        "Bières", "piece", 206, 187, 400],
    ["Carolus gouden",           "Bières", "piece", 241, 219, nil],
    ["Wout (Vaillante, Tiestu)", "Bières", "piece", 157, 143, 400],
    ["Badjawe brune",            "Bières", "piece", 220, 200, 400],
    ["Brune des braves",         "Bières", "piece", 218, 198, nil],
    ["Trottinette",              "Bières", "piece", 200, 182, 350],
    ["Trottinette passion",      "Bières", "piece", 200, 182, nil],
    ["Taras Boulba",             "Bières", "piece", 138, 125, 300],
    ["Mobius Triple",            "Bières", "piece", 116, 105, nil],

    ["Vin rouge bouteille",      "Vin", "piece",   800, nil, 1500],
    ["Vin rosé bouteille",       "Vin", "piece",   800, nil, 1500],
    ["Vin blanc bouteille",      "Vin", "piece",   800, nil, 1500],
    ["Vin verre",                "Vin", "portion", 176, 160, 300],

    ["Eau pétillante 1 L",       "Softs", "piece",   97,  88, 100],
    ["Jus de pomme 3 L",         "Softs", "piece",  450, 409, nil],
    ["Jus de pomme 1 L",         "Softs", "piece",  165, 150, 400],
    ["Jus de pomme verre",       "Softs", "portion", 50, nil, 200],
    ["Tisane",                   "Softs", "portion", 50, nil, 200],
    ["Bionina",                  "Softs", "piece",  165, 150, 300],
    ["Whole Earth",              "Softs", "piece",  204, 185, nil],
    ["Sirop steph",              "Softs", "portion", 50, nil, 150],
    ["Kombucha",                 "Softs", "piece",  307, 279, 500],
    ["Kefir (Eau Vertueuse)",    "Softs", "piece",  141, 128, 300],

    ["Chips ReBel",              "Snacks", "piece", 281, 255, 400],
    ["Chips Waltson",            "Snacks", "piece", 314, 285, nil],

    ["Café/Thé",                 "Autres", "portion",  50, nil, 200],
    ["Repas",                    "Autres", "portion", 500, nil, nil],
    ["Miel",                     "Autres", "piece",   800, nil, nil],
    ["Pizza Party",              "Autres", "portion", 200, nil, nil]
  ].freeze

  # Articles du seed de démo (#157) qui ne sont sur aucun des deux documents.
  # Retirés seulement s'ils n'ont jamais servi — une écriture qui les cite fige
  # leur sort, on ne touche pas au grand livre par une tâche de catalogue.
  BAR_OBSOLETES_2026_07 = ["Chimay bleue", "Jus de pomme"].freeze

  desc "Catalogue du bar relevé sur la fiche papier de juillet 2026 — dry-run par défaut, APPLY=1 pour écrire"
  task seed_bar_catalog_2026_07: :environment do
    apply = ENV["APPLY"] == "1"
    creees = maj = paliers = conserves = retires = 0

    ApplicationRecord.transaction do
      BAR_CATALOG_2026_07.each do |name, category, unit, member, purchase, public_price|
        item = CatalogItem.find_or_initialize_by(channel: "bar", name: name)
        nouveau = item.new_record?
        item.assign_attributes(category: category, unit: unit)
        item.active = true if nouveau

        if nouveau
          item.save!
          creees += 1
          puts "  + #{name.ljust(26)} #{category}"
        elsif item.changed?
          item.save!
          maj += 1
          puts "  ~ #{name.ljust(26)} #{item.previous_changes.keys.join(', ')}"
        end

        existant = item.catalog_prices.covering(BAR_2026_07).first

        # Un palier déjà en place n'est jamais écrasé : quelqu'un a pu corriger
        # un prix depuis, et la fiche papier n'est pas plus légitime que lui.
        # On le signale quand il diverge, c'est tout.
        if existant
          conserves += 1
          ecart = []
          ecart << "sourcier #{existant.member_price_cents} ≠ #{member}" if existant.member_price_cents != member
          if public_price && existant.public_price_cents != public_price
            ecart << "public #{existant.public_price_cents.inspect} ≠ #{public_price}"
          end
          puts "  ! #{name.ljust(26)} palier existant conservé — #{ecart.join(' / ')}" if ecart.any?
          next
        end

        item.catalog_prices.create!(
          active_from: BAR_2026_07,
          member_price_cents: member,
          purchase_price_cents: purchase,
          public_price_cents: public_price,
          note: "Fiche de bar papier juillet 2026 / carte août 2026"
        )
        paliers += 1
      end

      BAR_OBSOLETES_2026_07.each do |name|
        item = CatalogItem.find_by(channel: "bar", name: name)
        next if item.nil?

        ecritures = item.account_entries.count
        if ecritures.positive?
          puts "  ! #{name.ljust(26)} #{ecritures} écriture(s) rattachée(s) — CONSERVÉ"
          next
        end

        item.soft_delete!(validate: false)
        retires += 1
        puts "  - #{name.ljust(26)} retiré (jamais vendu)"
      end

      raise ActiveRecord::Rollback unless apply
    end

    puts "[finance:seed_bar_catalog_2026_07] #{creees} article(s) créé(s), #{maj} mis à jour, " \
         "#{paliers} palier(s) posé(s) au #{BAR_2026_07}, #{conserves} palier(s) déjà en place, " \
         "#{retires} article(s) retiré(s)"
    puts "[finance:seed_bar_catalog_2026_07] Rien n'a été écrit — relance avec APPLY=1." unless apply
  end

  # Familles de la fiche, dans l'ordre des colonnes. La valeur est ce qu'on
  # cherche dans le NOM du compte sourcier — les comptes s'appellent rarement
  # exactement comme la colonne d'une feuille A4.
  BAR_SHEET_FAMILIES_2026_07 = ["Frennet", "Vanhamme", "Hulet", "Fays", "Grignard"].freeze

  # Bâtonnets relevés, dans l'ordre des familles ci-dessus. Les colonnes Manon
  # et Emilie de la fiche sont hors périmètre (elles ne sont pas des ménages).
  BAR_SHEET_TALLIES_2026_07 = {
    "Moinette"                 => [2, 0, 4, 0, 0],
    "Ducassis"                 => [1, 0, 1, 1, 0],
    "Holy IPA"                 => [6, 1, 2, 0, 0],
    "Acid"                     => [0, 1, 0, 0, 0],
    "Big Nose"                 => [1, 0, 0, 1, 2],
    "Cambrée"                  => [0, 0, 1, 1, 0],
    "Topless"                  => [2, 0, 2, 0, 0],
    "Chinette"                 => [2, 0, 0, 1, 0],
    "Lupulus organicus"        => [3, 0, 1, 0, 0],
    "Wout (Vaillante, Tiestu)" => [3, 0, 4, 1, 0],
    "Brune des braves"         => [2, 0, 2, 1, 0],
    "Taras Boulba"             => [8, 3, 5, 0, 0],
    "Mobius Triple"            => [6, 3, 1, 0, 0],
    "Vin rosé bouteille"       => [3, 0, 1, 0, 5],
    "Vin blanc bouteille"      => [0, 0, 1, 1, 0],
    "Vin verre"                => [1, 0, 2, 5, 1],
    "Eau pétillante 1 L"       => [0, 0, 0, 2, 3],
    "Jus de pomme 3 L"         => [0, 0, 0, 2, 0],
    "Jus de pomme 1 L"         => [0, 0, 0, 1, 0],
    "Bionina"                  => [5, 5, 5, 11, 0],
    "Chips ReBel"              => [7, 5, 5, 2, 0],
    "Pizza Party"              => [4, 3, 3, 2, 1]
  }.freeze

  desc "Fiche de bar de juillet 2026 : création + encodage des bâtonnets — dry-run par défaut, APPLY=1 pour écrire"
  task import_bar_sheet_2026_07: :environment do
    apply = ENV["APPLY"] == "1"

    # 1. Les comptes. On s'arrête net si l'un d'eux est introuvable ou ambigu :
    #    encoder la conso d'une famille sur le compte d'une autre est le seul
    #    dégât vraiment coûteux ici.
    comptes = BAR_SHEET_FAMILIES_2026_07.to_h do |famille|
      trouves = MemberAccount.actives.where("name ILIKE ?", "%#{famille}%").to_a
      [famille, trouves]
    end

    if comptes.any? { |_, trouves| trouves.size != 1 }
      puts "[finance:import_bar_sheet_2026_07] Correspondance des comptes impossible :"
      comptes.each do |famille, trouves|
        etat = case trouves.size
               when 0 then "AUCUN compte"
               when 1 then "→ #{trouves.first.name} (#{trouves.first.code})"
               else "AMBIGU : #{trouves.map(&:name).join(' / ')}"
               end
        puts "  #{famille.ljust(12)} #{etat}"
      end
      puts "\nComptes actifs existants :"
      MemberAccount.actives.ordered.each { |a| puts "  #{a.code}  #{a.kind_label.ljust(9)} #{a.name}" }
      abort "\nAjuste BAR_SHEET_FAMILIES_2026_07 dans lib/tasks/finance.rake avant de relancer."
    end

    comptes = comptes.transform_values(&:first)
    comptes.each { |famille, compte| puts "  #{famille.ljust(12)} → #{compte.name} (#{compte.code})" }

    # 2. Les articles. Idem : un article manquant fausserait le total en silence.
    articles = CatalogItem.active.for_channel("bar").index_by(&:name)
    manquants = BAR_SHEET_TALLIES_2026_07.keys - articles.keys
    if manquants.any?
      abort "\n[finance:import_bar_sheet_2026_07] Articles absents du catalogue : #{manquants.join(', ')}." \
            "\nLance d'abord finance:seed_bar_catalog_2026_07 APPLY=1."
    end

    rapport = nil
    totaux = Hash.new(0)

    ApplicationRecord.transaction do
      fiche = PaperSheet.find_or_initialize_by(period_month: BAR_2026_07, channel: "bar")
      nouvelle = fiche.new_record?
      fiche.entry_mode = "quantity"
      fiche.notes = "Reprise de la feuille A4 « Fiche de BAR — juillet 2026 ». " \
                    "Colonnes Manon et Emilie non reprises."
      fiche.save!

      cells = Hash.new { |h, k| h[k] = {} }
      BAR_SHEET_TALLIES_2026_07.each do |nom, quantites|
        article = articles.fetch(nom)
        prix = fiche.price_for(article)
        abort "\nPas de prix pour « #{nom} » au #{fiche.entry_date}." if prix.nil?

        quantites.each_with_index do |quantite, index|
          next if quantite.zero?

          compte = comptes.fetch(BAR_SHEET_FAMILIES_2026_07[index])
          cells[compte.id][article.id] = quantite
          totaux[compte.name] += quantite * prix.member_price_cents
        end
      end

      rapport = Finance::EncodePaperSheet.new(
        sheet: fiche, cells: cells, entry_mode: "quantity", whodunnit: "rake:import_bar_sheet_2026_07"
      ).run!

      puts "\n  Fiche ##{fiche.id} (#{nouvelle ? 'créée' : 'déjà existante'}) — écritures datées du #{fiche.entry_date}"
      puts "  #{rapport.summary}"

      raise ActiveRecord::Rollback unless apply
    end

    puts "\n  Totaux par ménage :"
    totaux.sort_by { |_, cents| -cents }.each do |nom, cents|
      puts "    #{nom.ljust(28)} #{format('%8.2f', cents / 100.0)} €"
    end
    puts "    #{'TOTAL'.ljust(28)} #{format('%8.2f', totaux.values.sum / 100.0)} €"

    puts "[finance:import_bar_sheet_2026_07] Rien n'a été écrit — relance avec APPLY=1." unless apply
  end
end
