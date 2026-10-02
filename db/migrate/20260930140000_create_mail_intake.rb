# La messagerie, phase 1 : `compta@` → factures d'achat.
#
# Trois tables, parce qu'il y a trois choses distinctes. Une BOÎTE (le compte
# IMAP qu'on lit, et le curseur qui dit où on s'est arrêté), un MAIL (ce qui
# est arrivé, et ce qu'un humain en a fait), une PIÈCE (le PDF qui deviendra une
# facture). Une pièce n'est pas une colonne du mail : un fournisseur envoie
# souvent la facture ET ses conditions générales, et seule la première se
# comptabilise.
#
# Le mot de passe IMAP n'est PAS ici : le dépôt est public et la base se copie
# en local. Il vit dans l'ENV (`MAIL_PASSWORD_COMPTA`).
class CreateMailIntake < ActiveRecord::Migration[8.1]
  def change
    create_table :mail_accounts do |t|
      t.string :address, null: false
      t.string :purpose, null: false
      t.string :imap_host, null: false, default: "box.les4sources.be"
      t.string :folder, null: false, default: "INBOX"
      # Le curseur. UIDVALIDITY change quand le serveur renumérote la boîte :
      # le dernier UID lu ne veut alors plus rien dire et on repart de zéro,
      # l'unicité du Message-ID empêchant les doublons.
      t.bigint :uid_validity
      t.bigint :last_uid, null: false, default: 0
      t.datetime :last_synced_at
      t.text :last_error
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :mail_accounts, :address, unique: true

    create_table :mail_messages do |t|
      t.references :mail_account, null: false, foreign_key: true
      t.string :message_id, null: false
      t.bigint :imap_uid
      t.string :from_address
      t.string :from_name
      t.string :subject
      t.datetime :received_at, null: false
      t.text :body_text
      t.string :status, null: false, default: "pending"
      # La proposition de Jev pour le mail entier (nature, action suggérée).
      t.jsonb :triage, null: false, default: {}
      t.datetime :analyzed_at
      t.references :handled_by, foreign_key: { to_table: :users }
      t.datetime :handled_at
      t.timestamps
    end
    add_index :mail_messages, %i[mail_account_id message_id], unique: true
    add_index :mail_messages, %i[status received_at]

    create_table :mail_attachments do |t|
      t.references :mail_message, null: false, foreign_key: true
      t.references :purchase_invoice, foreign_key: true
      t.string :filename, null: false
      t.string :content_type, null: false
      t.string :sha256, null: false
      t.text :text_content
      # Ce que le code et Jev proposent pour la facture : chaque valeur garde sa
      # source (`code` ou `jev`) et, pour Jev, sa confiance.
      t.jsonb :proposal, null: false, default: {}
      t.timestamps
    end
    add_index :mail_attachments, :sha256
  end
end
