# Le moteur de partie double (issue #177, lot B).
#
# Une écriture, N lignes, et une seule règle qui les tient : la somme des débits
# égale la somme des crédits. C'est cette règle qui fait qu'une comptabilité se
# contredit toute seule quand on se trompe, au lieu d'attendre qu'un humain
# remarque l'écart six mois plus tard.
#
# Le point de conception qui décide du succès : `source_type` / `source_id`.
# Toute écriture POINTE le document métier qui l'a produite — une ligne bancaire
# ventilée, un décompte, un règlement. C'est ce qui permet de tenir la promesse
# « la double écriture se génère, elle ne se saisit jamais » : sans document
# source, une écriture n'a pas de raison d'exister. L'index unique sur (source,
# journal) rend la passation idempotente : repasser le même document ne le
# comptabilise pas deux fois.
#
# `reversal_of_id` plutôt qu'une suppression : une écriture passée ne disparaît
# jamais, elle se contre-passe. C'est la seule façon de garder une numérotation
# sans trou, et un trou dans la numérotation est exactement ce qu'un contrôle
# fiscal regarde en premier.
class CreateJournalEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :journal_entries do |t|
      t.references :fiscal_year, null: false, foreign_key: true
      t.references :legal_entity, null: false, foreign_key: true
      t.string :journal, null: false
      t.integer :number, null: false
      t.date :entry_date, null: false
      t.string :label, null: false
      t.string :source_type
      t.bigint :source_id
      t.datetime :posted_at, null: false
      t.datetime :locked_at
      t.bigint :reversal_of_id
      t.string :whodunnit
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :journal_entries, [:fiscal_year_id, :journal, :number],
              unique: true, name: "index_journal_entries_on_sequence"
    add_index :journal_entries, [:source_type, :source_id, :journal],
              unique: true, where: "source_id IS NOT NULL",
              name: "index_journal_entries_on_source"
    add_index :journal_entries, :entry_date
    add_index :journal_entries, :deleted_at
    add_foreign_key :journal_entries, :journal_entries, column: :reversal_of_id

    create_table :journal_lines do |t|
      t.references :journal_entry, null: false, foreign_key: true
      t.references :general_account, null: false, foreign_key: true
      t.references :analytic_account, foreign_key: true
      t.references :team, foreign_key: true
      t.bigint :debit_cents, null: false, default: 0
      t.bigint :credit_cents, null: false, default: 0
      t.string :label
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :journal_lines, :deleted_at

    # Une ligne porte un débit OU un crédit. La contrainte est en base et pas
    # seulement dans le modèle : une ligne à double sens rend la balance
    # ininterprétable, et ce genre d'erreur arrive par script, pas par écran.
    execute <<~SQL
      ALTER TABLE journal_lines
      ADD CONSTRAINT journal_lines_one_side_only
      CHECK (
        debit_cents >= 0 AND credit_cents >= 0
        AND (debit_cents = 0 OR credit_cents = 0)
        AND (debit_cents > 0 OR credit_cents > 0)
      )
    SQL
  end
end
