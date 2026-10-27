# Bascule vers Amazon SES : l'identifiant SES du message (pour retrouver
# l'email quand SES signale un rebond ou une plainte) et le problème de remise
# éventuel, affiché sur la fiche client.
class AddSesTrackingToSentEmails < ActiveRecord::Migration[8.1]
  def change
    add_column :sent_emails, :ses_message_id, :string
    add_column :sent_emails, :delivery_issue, :string
    add_column :sent_emails, :delivery_issue_detail, :string
    add_column :sent_emails, :delivery_issue_at, :datetime
    add_index :sent_emails, :ses_message_id, where: "ses_message_id IS NOT NULL"
  end
end
