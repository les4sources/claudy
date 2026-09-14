# Préférence par utilisateur (epic #242, décision 3) : recevoir aussi ses
# notifications par email. Vrai par défaut — une notification qui n'arrive nulle
# part ne sert à rien tant que personne n'a ouvert Claudy de la journée.
class AddNotifyByEmailToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :notify_by_email, :boolean, null: false, default: true
  end
end
