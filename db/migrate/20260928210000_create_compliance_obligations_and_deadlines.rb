# L'échéancier comptable (Michael, 2026-09-28) — ce qui vivait dans la base
# Notion « Échéancier comptable ».
#
# Deux tables parce qu'il y a deux faits : la RÈGLE (« la TVA de la SRL se
# déclare chaque trimestre ») s'écrit une fois ; l'ÉCHÉANCE (« TVA T3 2026, pour
# le 20 octobre ») est ce qu'on fait, coche et prouve. Notion ne connaissait que
# la seconde, d'où les lignes recopiées à la main à chaque trimestre.
class CreateComplianceObligationsAndDeadlines < ActiveRecord::Migration[8.1]
  def change
    create_table :compliance_obligations do |t|
      t.string :title, null: false
      t.references :legal_entity, null: false, foreign_key: true
      t.string :frequency, null: false, default: "yearly"
      t.date :first_due_on, null: false
      t.date :ends_on
      t.string :covers, null: false, default: "previous"
      t.boolean :payment, null: false, default: false
      t.references :responsible_user, foreign_key: { to_table: :users }
      t.text :instructions
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :compliance_obligations, :deleted_at
    add_index :compliance_obligations, %i[legal_entity_id title], unique: true,
                                                                  where: "deleted_at IS NULL",
                                                                  name: "index_compliance_obligations_on_entity_and_title"

    create_table :compliance_deadlines do |t|
      t.references :compliance_obligation, null: false, foreign_key: true
      t.date :period_start, null: false
      t.date :due_on, null: false
      t.string :status, null: false, default: "todo"
      t.date :done_on
      t.references :done_by_user, foreign_key: { to_table: :users }
      t.text :note
      t.references :purchase_invoice, foreign_key: true
      t.string :last_reminder_stage
      t.date :last_reminded_on
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :compliance_deadlines, :deleted_at
    add_index :compliance_deadlines, :due_on
    add_index :compliance_deadlines, %i[compliance_obligation_id period_start], unique: true,
                                                                                 where: "deleted_at IS NULL",
                                                                                 name: "index_compliance_deadlines_on_obligation_and_period"
  end
end
