class AddConfirmationEmailSentAtToStays < ActiveRecord::Migration[8.1]
  # Horodatage du SEUL email « votre séjour est confirmé » (issue Malau
  # 2026-08-20). Même rôle que `activity_email_sent_at` et
  # `balance_reminder_sent_at` : il rend l'envoi idempotent, si bien qu'un
  # aller-retour pending → confirmed → pending → confirmed ne renvoie pas
  # l'email. Le renvoi manuel depuis la fiche admin l'écrase volontairement.
  def change
    add_column :stays, :confirmation_email_sent_at, :datetime
  end
end
