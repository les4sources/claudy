# Recalcule le statut de paiement DÉRIVÉ de chaque séjour (2026-07-21) : le
# backfill facturation espaces a laissé des statuts périmés (ex. séjour soldé
# affiché « En attente »). Idempotente, ne touche que la colonne dérivée.
namespace :stays do
  desc "Recalcule payment_status de tous les séjours (dry-run par défaut, APPLY=1)"
  task recompute_payment_statuses: :environment do
    apply = ENV["APPLY"] == "1"
    changed = []
    Stay.find_each do |stay|
      before = stay.payment_status
      stay.set_payment_status # non-bang : calcule + sauve ; en dry-run on annule
      after = stay.payment_status
      if before != after
        changed << "##{stay.id} #{before} → #{after}"
        stay.update_column(:payment_status, before) unless apply
      end
    end
    puts "=== stays:recompute_payment_statuses (#{apply ? "RÉEL" : "DRY-RUN"}) ==="
    puts "Statuts à corriger : #{changed.size}"
    changed.first(30).each { |line| puts "  #{line}" }
    puts apply ? "OK — appliqué." : "DRY-RUN — statuts restaurés. APPLY=1 pour appliquer."
  end
end
