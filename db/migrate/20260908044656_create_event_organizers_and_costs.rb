# Epic #245, phase 1 — ce qu'il faut pour partager la recette d'un événement :
# qui l'organise (et dans quelle proportion), quel taux lui revient, quel pôle
# le porte, et quels frais fixes se déduisent avant le partage.
class CreateEventOrganizersAndCosts < ActiveRecord::Migration[8.1]
  def change
    create_table :event_organizers do |t|
      t.references :event, null: false, foreign_key: true
      t.references :human, null: false, foreign_key: true
      # La part se répartit au prorata des poids ; tous à 1 = parts égales.
      t.integer :weight, null: false, default: 1

      t.timestamps
    end
    add_index :event_organizers, %i[event_id human_id], unique: true

    create_table :event_costs do |t|
      t.references :event, null: false, foreign_key: true
      t.string  :label, null: false
      t.integer :amount_cents, null: false, default: 0
      t.string  :kind, null: false, default: "other"
      # Vers la pièce quand elle existe : une réservation d'espace aujourd'hui,
      # une facture d'achat ou une note de frais quand ces modèles arriveront.
      t.references :source, polymorphic: true
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :event_costs, :deleted_at

    # 70 % par défaut, mais le taux est PAR ÉVÉNEMENT : les 30 % retenus sont
    # contestés, et le disc golf n'en laisse aucun.
    add_column :events, :organizer_share_percent, :integer
    add_reference :events, :team, foreign_key: true
  end
end
