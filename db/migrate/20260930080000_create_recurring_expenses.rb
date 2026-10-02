# Les charges fixes de la trésorerie (2026-09-30) : un abonnement Voo, une
# assurance, un prêt — une règle écrite une fois (montant, fréquence, première
# échéance) plutôt qu'une facture recopiée chaque mois. La trésorerie en projette
# les occurrences ; rien n'est comptabilisé tant que la vraie facture ou le vrai
# prélèvement n'arrive pas.
#
# Table distincte de `recurring_charges`, qui porte les charges des comptes
# sourciers (ce que les habitants DOIVENT) : ici, c'est ce que la maison PAIE.
class CreateRecurringExpenses < ActiveRecord::Migration[8.1]
  def change
    create_table :recurring_expenses do |t|
      t.references :legal_entity, null: false, foreign_key: true
      t.references :third_party, foreign_key: true
      t.references :general_account, foreign_key: true
      t.string :label, null: false
      t.bigint :amount_cents, null: false
      t.string :frequency, null: false, default: "monthly"
      t.date :first_due_on, null: false
      t.date :ends_on
      t.boolean :active, null: false, default: true
      t.text :notes
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :recurring_expenses, :deleted_at
  end
end
