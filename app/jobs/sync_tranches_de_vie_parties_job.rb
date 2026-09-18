# Passage quotidien sur les Pizza Party rattachées (issue #339) : ce qui a été
# annulé ou remboursé chez Tranches de Vie sort du total du séjour et de
# l'encaissé ici.
#
# Planification : ce projet n'a pas de mécanisme de récurrence applicatif
# (ni Solid Queue, ni sidekiq-cron). Comme les autres tâches quotidiennes, le
# passage se déclenche par le CRON DE HATCHBOX sur la rake
# `tranches_de_vie:sync_parties` (voir README, « Tâches planifiées »).
class SyncTranchesDeViePartiesJob < ApplicationJob
  queue_as :default

  def perform
    unless TranchesDeVie::Client.configured?
      Rails.logger.info("[SyncTranchesDeViePartiesJob] TRANCHESDEVIE_API_KEY absente : synchronisation ignorée")
      return :skipped
    end

    service = TranchesDeVie::SyncPartyReservations.new
    service.run

    Rails.logger.info(
      "[SyncTranchesDeViePartiesJob] #{service.checked} vérifiée(s), #{service.changed} mise(s) à jour, " \
      "#{service.failures.size} en échec"
    )
    service
  end
end
