# Le PDF embarqué dans une facture électronique UBL devient une pièce à part
# entière (celle qu'on consulte et qu'on joint à la facture), mais il reste
# rattaché au XML dont il vient : c'est le XML qui porte les valeurs exactes.
class AddEmbeddedInToMailAttachments < ActiveRecord::Migration[8.1]
  def change
    add_reference :mail_attachments, :embedded_in, foreign_key: { to_table: :mail_attachments }
  end
end
