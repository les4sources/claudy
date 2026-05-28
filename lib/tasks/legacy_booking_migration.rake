namespace :claudy do
  namespace :migrate do
    desc "Migre tout l'historique Booking + SpaceBooking vers le graphe Customer/Stay/StayItem. " \
         "Idempotent. Dry-run : DRY_RUN=true rake claudy:migrate:legacy_bookings_to_stays"
    task legacy_bookings_to_stays: :environment do
      dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"]).present?

      mode = dry_run ? "DRY-RUN (aucune écriture)" : "RÉEL (écriture en base)"
      puts "== Migration legacy -> stays : #{mode} =="

      runner = LegacyBookingMigration::Runner.new(dry_run: dry_run, logger: Rails.logger)
      report = runner.run

      puts report.to_s

      if runner.error.present?
        warn "ÉCHEC : #{runner.error_message}"
        exit 1
      end
    end
  end
end
