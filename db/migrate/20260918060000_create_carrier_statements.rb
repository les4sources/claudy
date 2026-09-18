# Le relevé de rémunération d'un porteur d'activité (epic #244, phase 3).
#
# Une prestation tenue porte sa rémunération figée (`carrier_fee_cents`, phase 1)
# mais rien ne la payait. Le relevé rassemble les prestations `held` d'une
# période, fige leur total, passe l'écriture et devient une dette à virer.
#
# `experience_booking_id` est UNIQUE sur les lignes : une prestation n'est
# relevée qu'une fois. C'est l'invariant qui empêche de payer deux fois.
class CreateCarrierStatements < ActiveRecord::Migration[8.1]
  def change
    create_table :carrier_statements do |t|
      t.references :human, null: false, foreign_key: true

      t.date :period_from, null: false
      t.date :period_to, null: false
      t.integer :total_fee_cents, null: false, default: 0

      t.string :status, null: false, default: "draft"
      t.string :token, null: false

      t.datetime :issued_at
      t.datetime :sent_at
      t.date     :paid_on
      t.datetime :posted_at
      t.datetime :deleted_at

      t.timestamps
    end

    create_table :carrier_statement_lines do |t|
      t.references :carrier_statement, null: false, foreign_key: true
      t.references :experience_booking, null: false, foreign_key: true

      t.integer :fee_cents, null: false, default: 0
      t.string  :label
      t.date    :occurred_on

      t.timestamps
    end

    add_index :carrier_statements, :token, unique: true
    add_index :carrier_statements, :status
    add_index :carrier_statements, :deleted_at
    add_index :carrier_statement_lines, :experience_booking_id, unique: true,
              name: "index_carrier_statement_lines_on_booking_unique"
  end
end
