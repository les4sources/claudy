# Synchronisation des versements Stripe (issue #187).
#
# Dry-run par DÉFAUT, comme tous les rakes de ce dépôt. Une synchronisation qui
# écrit sans qu'on l'ait demandé est une synchronisation qu'on n'ose plus
# lancer.
#
# `SINCE=2026-01-01` règle le rattrapage de l'année en une exécution : les
# commissions 2026 ne sont ventilées nulle part aujourd'hui.
namespace :stripe do
  desc "Synchronise les versements Stripe — SINCE=2026-01-01 [ACCOUNT=claudy], dry-run par défaut, APPLY=1 pour écrire"
  task sync_payouts: :environment do
    since = (ENV["SINCE"].presence && Date.parse(ENV["SINCE"])) || Date.current.beginning_of_year
    account = (ENV["ACCOUNT"].presence || "claudy").to_sym
    apply = ENV["APPLY"] == "1"

    report = Stripe::SyncPayouts.new(account_key: account, since: since, apply: apply).run!

    puts "[stripe:sync_payouts] compte #{StripeService.label_for(account)}, depuis #{since}"
    puts "  #{report[:payouts]} versement(s), #{report[:transactions]} transaction(s)"
    puts "  #{report[:created_payouts]} versement(s) #{apply ? 'créé(s)' : 'à créer'}, " \
         "#{report[:created_transactions]} transaction(s) #{apply ? 'créée(s)' : 'à créer'}"
    puts "  DRY-RUN — relance avec APPLY=1 pour écrire." unless apply
    report[:messages].each { |message| puts "  ! #{message}" }
  rescue StripeService::MissingKey, StripeService::UnknownAccount => e
    puts "[stripe:sync_payouts] #{e.message}"
    exit 1
  end
end
