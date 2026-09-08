namespace :activities do
  desc "Complète la rémunération figée des réservations déjà confirmées (epic #244). Dry-run par défaut, APPLY=1 pour écrire."
  task backfill_carrier_fees: :environment do
    apply  = ENV["APPLY"].present?
    result = Activities::BackfillCarrierFees.new(dry_run: !apply).run

    puts "[activities:backfill_carrier_fees] #{result}"
    result.filled.each { |ligne| puts "  - #{ligne}" }
    if result.without_duration.any?
      puts "  Sans durée en heures — complète la durée de l'activité puis relance :"
      result.without_duration.each { |ligne| puts "    - #{ligne}" }
    end
    puts "[activities:backfill_carrier_fees] Rien n'a été écrit — relance avec APPLY=1." unless apply
  end
end
