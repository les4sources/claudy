require Rails.root.join("lib/coda/fingerprint")

# L'idempotence de l'import CODA passe du numéro de relevé à l'identité du
# mouvement (voir `Coda::Fingerprint`).
#
# Le remplissage des lignes déjà importées fait partie de la migration, et non
# d'une tâche à lancer ensuite : entre les deux, tout import verrait un journal
# sans empreintes et recréerait des lignes déjà présentes. Une reprise oubliée
# est le mode de panne le plus probable de ce déploiement, alors on le rend
# impossible.
class AddFingerprintToCashEntries < ActiveRecord::Migration[8.1]
  def up
    add_column :cash_entries, :fingerprint, :string

    backfill_fingerprints

    add_index :cash_entries, [:cash_account_id, :fingerprint], unique: true,
              where: "fingerprint IS NOT NULL", name: "index_cash_entries_on_fingerprint"

    # Le relevé `000` de Triodos revient à chaque export : l'unicité par année
    # civile faisait passer tout relevé suivant pour un doublon du premier.
    # L'unicité qui a du sens est celle du relevé DANS SON FICHIER.
    remove_index :coda_statements, name: "index_coda_statements_on_account_and_sequence"
    add_index :coda_statements, [:coda_import_id, :cash_account_id, :sequence_number],
              unique: true, name: "index_coda_statements_on_import_and_sequence"
  end

  def down
    remove_index :coda_statements, name: "index_coda_statements_on_import_and_sequence"
    add_index :coda_statements, [:cash_account_id, :period_year, :sequence_number],
              unique: true, name: "index_coda_statements_on_account_and_sequence"

    remove_index :cash_entries, name: "index_cash_entries_on_fingerprint"
    remove_column :cash_entries, :fingerprint
  end

  private

  # Les lignes soft-deletées comptent : elles occupent leur rang d'occurrence, et
  # les ignorer décalerait celui des lignes vivantes qui les suivent.
  def backfill_fingerprints
    occurrences = Hash.new(0)
    updates = []

    select_all(<<~SQL.squish).each do |row|
      SELECT id, cash_account_id, entry_date, value_date, amount_cents,
             counterparty_iban, counterparty_name, communication, transaction_code
      FROM cash_entries ORDER BY cash_account_id, id
    SQL
      digest = Coda::Fingerprint.digest(
        entry_date: row["entry_date"], value_date: row["value_date"],
        amount_cents: row["amount_cents"], counterparty_iban: row["counterparty_iban"],
        counterparty_name: row["counterparty_name"], communication: row["communication"],
        transaction_code: row["transaction_code"]
      )
      key = [row["cash_account_id"], digest]
      occurrences[key] += 1
      updates << [row["id"], format("%<digest>s:%<occurrence>02d", digest: digest, occurrence: occurrences[key])]
    end

    updates.each_slice(500) do |slice|
      valeurs = slice.map { |id, fingerprint| "(#{id.to_i}, #{quote(fingerprint)})" }.join(", ")
      execute(<<~SQL.squish)
        UPDATE cash_entries SET fingerprint = v.fingerprint
        FROM (VALUES #{valeurs}) AS v(id, fingerprint)
        WHERE cash_entries.id = v.id
      SQL
    end

    say "#{updates.size} ligne(s) de trésorerie dotée(s) d'une empreinte."
  end

  def select_all(sql) = connection.select_all(sql)
  def quote(value) = connection.quote(value)
end
