class CreateSentEmails < ActiveRecord::Migration[7.0]
  def change
    create_table :sent_emails do |t|
      t.references :customer, null: false, foreign_key: true
      t.citext :to_email, null: false
      t.string :subject
      t.text :body_html
      t.text :body_text
      # Mailer d'origine, ex. "BookingMailer#booking_confirmed". Nul pour les
      # lignes rapatriées de Postmark (l'API ne connaît que le tag).
      t.string :mailer
      t.string :tag
      # MessageID Postmark — clé de dédoublonnage entre le journal local et le
      # backfill : un email déjà journalisé à l'envoi ne sera pas ré-importé.
      t.string :postmark_message_id
      t.datetime :sent_at, null: false
      t.string :source, null: false, default: "app"

      t.timestamps
    end

    add_index :sent_emails, [:customer_id, :sent_at]
    add_index :sent_emails, :postmark_message_id, unique: true, where: "postmark_message_id IS NOT NULL"
  end
end
