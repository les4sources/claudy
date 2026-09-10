namespace :activities do
  desc "Rappelle à chaque porteur ses activités passées sans verdict de tenue (epic #244). Dry-run par défaut, APPLY=1 pour envoyer."
  task outcome_reminders: :environment do
    apply  = ENV["APPLY"].present?
    result = Activities::OutcomeReminders.new(dry_run: !apply).run

    puts "[activities:outcome_reminders] #{result}"
    result.carriers.each { |ligne| puts "  - #{ligne}" }
    if result.skipped.any?
      puts "  Sans adresse email — à relancer à la main :"
      result.skipped.each { |ligne| puts "    - #{ligne}" }
    end
    puts "[activities:outcome_reminders] Aucun email envoyé — relance avec APPLY=1." unless apply
  end

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
