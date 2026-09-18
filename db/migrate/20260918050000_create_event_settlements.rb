# Le règlement d'un événement (epic #245, phase 3) : le calcul de la part des
# organisateurs, FIGÉ au moment où on décide de payer.
#
# Pourquoi figer : la part se recalcule à chaque affichage tant que l'événement
# n'est pas réglé — une recette qui arrive après coup la ferait bouger. Une fois
# le virement décidé et l'écriture passée, le chiffre ne doit plus changer sous
# les pieds de la compta ; une correction passe par une contre-passation.
class CreateEventSettlements < ActiveRecord::Migration[8.1]
  def change
    create_table :event_settlements do |t|
      t.references :event, null: false, foreign_key: true, index: { unique: true }

      t.integer :revenue_cents, null: false, default: 0
      t.integer :costs_cents, null: false, default: 0
      t.integer :base_cents, null: false, default: 0
      t.integer :organizer_share_percent, null: false, default: 0
      t.integer :organizers_cents, null: false, default: 0
      t.integer :house_cents, null: false, default: 0

      t.string   :status, null: false, default: "issued"
      t.datetime :issued_at
      t.datetime :posted_at

      t.timestamps
    end

    create_table :event_settlement_lines do |t|
      t.references :event_settlement, null: false, foreign_key: true
      t.references :human, null: false, foreign_key: true

      t.integer :weight, null: false, default: 1
      t.integer :amount_cents, null: false, default: 0
      t.date    :paid_on

      t.timestamps
    end

    add_index :event_settlements, :status
    add_index :event_settlement_lines, %i[event_settlement_id human_id], unique: true,
              name: "index_event_settlement_lines_on_settlement_and_human"
  end
end
