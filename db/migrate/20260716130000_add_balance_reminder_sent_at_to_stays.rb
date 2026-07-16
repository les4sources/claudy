class AddBalanceReminderSentAtToStays < ActiveRecord::Migration[7.0]
  # Idempotence de la relance solde J-14 (epic #55, Phase 5) : on horodate le
  # dernier envoi pour ne jamais renvoyer la relance à chaque passage du cron.
  # Colonne nullable → tous les séjours existants restent valides (aucune
  # relance encore émise = NULL). `add_column` est réversible automatiquement.
  def change
    add_column :stays, :balance_reminder_sent_at, :datetime
  end
end
