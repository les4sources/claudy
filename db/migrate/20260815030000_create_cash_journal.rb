# Le journal de trésorerie (issue #179, lot B2).
#
# La règle anti-double-compte du lot tient dans le schéma : une recette n'entre
# au journal QU'UNE FOIS, quand l'argent touche un compte de trésorerie. Les
# séjours, les paiements et les décomptes sont des DOCUMENTS que les allocations
# pointent — jamais des montants qu'on additionne. Sans ça, un séjour payé
# compté à la fois depuis la réservation et depuis le virement double le chiffre
# d'affaires, et plus personne ne sait lequel des deux chiffres croire.
#
# Deux détails qui portent tout le reste :
#
# `external_ref` unique par compte rend les imports rejouables sans peur — c'est
# ce qui permettra à l'import CODA (B3) de tourner deux fois sans doubler un
# relevé.
#
# `legal_entity_id` est sur l'ALLOCATION et pas sur le compte bancaire. Une
# facture de travaux de la Société simple payée depuis le compte de la Fondation
# est un mouvement Fondation et une charge Société simple. Mettre l'entité sur le
# compte forcerait à mentir sur l'une des deux.
class CreateCashJournal < ActiveRecord::Migration[8.1]
  def change
    create_table :cash_entries do |t|
      t.references :cash_account, null: false, foreign_key: true
      t.date :entry_date, null: false
      t.date :value_date
      t.bigint :amount_cents, null: false
      t.string :label, null: false
      t.string :counterparty_name
      t.string :counterparty_iban
      t.string :communication
      t.string :external_ref
      t.string :statement_ref
      t.string :status, null: false, default: "pending"
      t.string :excluded_reason
      t.datetime :allocated_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :cash_entries, [:cash_account_id, :external_ref],
              unique: true, where: "external_ref IS NOT NULL",
              name: "index_cash_entries_on_external_ref"
    add_index :cash_entries, :entry_date
    add_index :cash_entries, :status
    add_index :cash_entries, :deleted_at

    create_table :cash_allocations do |t|
      t.references :cash_entry, null: false, foreign_key: true
      t.references :general_account, null: false, foreign_key: true
      t.references :analytic_account, foreign_key: true
      t.references :team, foreign_key: true
      t.references :legal_entity, null: false, foreign_key: true
      t.bigint :amount_cents, null: false
      t.string :document_type
      t.bigint :document_id
      t.string :label
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :cash_allocations, [:document_type, :document_id]
    add_index :cash_allocations, :deleted_at

    # Une allocation à zéro n'affecte rien et fausse le compte des lignes
    # restantes : elle n'a pas de raison d'exister.
    execute <<~SQL
      ALTER TABLE cash_allocations
      ADD CONSTRAINT cash_allocations_non_zero CHECK (amount_cents <> 0)
    SQL

    execute <<~SQL
      ALTER TABLE cash_entries
      ADD CONSTRAINT cash_entries_non_zero CHECK (amount_cents <> 0)
    SQL
  end
end
