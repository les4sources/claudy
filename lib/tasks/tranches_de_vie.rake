namespace :tranches_de_vie do
  desc "Répercute les annulations et remboursements des Pizza Party depuis Tranches de Vie (quotidien, cron Hatchbox)"
  task sync_parties: :environment do
    result = SyncTranchesDeViePartiesJob.perform_now
    next puts "TRANCHESDEVIE_API_KEY absente : rien à faire." if result == :skipped

    puts "Pizza Party : #{result.checked} vérifiée(s), #{result.changed} mise(s) à jour."
    result.failures.each { |id, message| puts "  ⚠ PartyReservation ##{id} : #{message}" }
  end
end
