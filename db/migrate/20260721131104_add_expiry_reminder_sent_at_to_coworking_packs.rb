# Epic #126, Phase 4 — clé d'idempotence du rappel J-30 avant expiration d'un
# pack (même pattern que `stays.balance_reminder_sent_at`) : une fois horodaté,
# le pack ne peut plus recevoir un second rappel, ce qui rend la rake
# quotidienne rejouable sans risque de doublon.
class AddExpiryReminderSentAtToCoworkingPacks < ActiveRecord::Migration[7.0]
  def change
    add_column :coworking_packs, :expiry_reminder_sent_at, :datetime
  end
end
