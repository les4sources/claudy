# Synchronisation d'un compte Stripe (issues #187 et #250).
#
# Dry-run par DÉFAUT, comme tous les rakes de ce dépôt. Une synchronisation qui
# écrit sans qu'on l'ait demandé est une synchronisation qu'on n'ose plus
# lancer.
#
# `SINCE=2026-01-01` règle le rattrapage de l'année en une exécution : les
# commissions 2026 ne sont ventilées nulle part aujourd'hui.
namespace :stripe do
  desc "Synchronise un compte Stripe — SINCE=2026-01-01 [ACCOUNT=claudy], dry-run par défaut, APPLY=1 pour écrire"
  task sync_payouts: :environment do
    since = (ENV["SINCE"].presence && Date.parse(ENV["SINCE"])) || Date.current.beginning_of_year
    account = (ENV["ACCOUNT"].presence || "claudy").to_sym
    apply = ENV["APPLY"] == "1"

    report = Stripe::SyncPayouts.new(account_key: account, since: since, apply: apply).run!

    puts "[stripe:sync_payouts] compte #{StripeService.label_for(account)}, depuis #{since} " \
         "(mode #{report[:mode]})"
    puts "  #{report[:payouts]} versement(s), #{report[:transactions]} transaction(s)"
    puts "  #{report[:created_payouts]} versement(s) #{apply ? 'créé(s)' : 'à créer'}, " \
         "#{report[:created_transactions]} transaction(s) #{apply ? 'créée(s)' : 'à créer'}"
    puts "  #{report[:created_entries]} ligne(s) de trésorerie créée(s)." if report[:mode] == "ledger" && apply

    # Le rapport des catégories est ce qui permet de créer les correspondances
    # AVANT le premier APPLY=1 : sans lui, on découvre les catégories manquantes
    # en regardant la file « À affecter » se remplir.
    if report[:categories].present?
      puts "  Catégories rencontrées :"
      report[:categories].each do |row|
        marque = row[:mapped] ? "✔" : "✗ sans correspondance"
        puts "    #{(row[:category] || 'sans catégorie').ljust(24)} " \
             "#{row[:count].to_s.rjust(5)} txn  " \
             "#{Money.new(row[:amount_cents], 'EUR').format.rjust(12)}  #{marque}"
      end
    end

    puts "  DRY-RUN — relance avec APPLY=1 pour écrire." unless apply
    report[:messages].each { |message| puts "  ! #{message}" }
  rescue StripeService::MissingKey, StripeService::UnknownAccount => e
    puts "[stripe:sync_payouts] #{e.message}"
    exit 1
  end

  # Créer une correspondance depuis le serveur, avant que l'écran de la phase 2
  # n'existe. Idempotent : relancer met à jour la correspondance existante.
  desc "Crée une correspondance de catégorie Stripe — ACCOUNT=… CATEGORY=…|none GENERAL_ACCOUNT=… [TEAM_ID=…] [ENTITY_ID=…]"
  task seed_category_mapping: :environment do
    account = ENV["ACCOUNT"].presence or abort("[stripe:seed_category_mapping] ACCOUNT= est obligatoire.")
    brut = ENV["CATEGORY"].presence or abort("[stripe:seed_category_mapping] CATEGORY= est obligatoire (`none` pour « sans catégorie »).")
    code = ENV["GENERAL_ACCOUNT"].presence or abort("[stripe:seed_category_mapping] GENERAL_ACCOUNT= est obligatoire.")

    category = brut == "none" ? nil : brut
    general_account = GeneralAccount.find_by(code: code)
    abort("[stripe:seed_category_mapping] Aucun compte général #{code}.") if general_account.nil?

    mapping = StripeCategoryMapping.for(account, category) ||
              StripeCategoryMapping.new(account_key: account, category: category)
    mapping.general_account = general_account
    mapping.team_id = ENV["TEAM_ID"].presence
    mapping.legal_entity_id = ENV["ENTITY_ID"].presence
    nouvelle = mapping.new_record?
    mapping.save!

    puts "[stripe:seed_category_mapping] #{nouvelle ? 'Créée' : 'Mise à jour'} : " \
         "#{account} / #{mapping.category_label} → #{general_account.code} #{general_account.name}" \
         "#{mapping.team ? " (pôle #{mapping.team.name})" : ''}"
  end
end
