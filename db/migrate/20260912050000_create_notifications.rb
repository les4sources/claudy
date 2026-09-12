# Le centre de notifications (epic #242, phase 2, décision 2).
#
# Une notification s'adresse à UN utilisateur précis et porte l'adresse de ce
# qu'il doit aller voir. C'est ce qui la distingue du flux « Activité récente »,
# qui dit ce qui a changé sans dire à qui ça s'adresse.
#
# `url` est obligatoire : une notification sans destination est une impasse.
# `notifiable` est facultatif — l'objet peut disparaître (soft-delete), la
# notification reste lisible grâce à son titre et son corps figés.
class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.string :kind, null: false
      t.references :notifiable, polymorphic: true, null: true
      t.string :title, null: false
      t.text :body
      t.string :url, null: false
      t.datetime :read_at
      t.datetime :emailed_at

      t.timestamps
    end

    # La cloche compte les non-lues d'un utilisateur à CHAQUE page : c'est la
    # requête la plus fréquente de la table, elle a droit à son index.
    add_index :notifications, %i[recipient_id read_at]
    add_index :notifications, %i[recipient_id created_at]
  end
end
