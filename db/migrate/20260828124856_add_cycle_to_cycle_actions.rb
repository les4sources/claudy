# Épic cycles — chaque action appartient désormais à un cycle, garde l'issue
# qu'elle a eue dans ce cycle (faite / reportée / abandonnée) et sait d'où elle
# vient quand elle a été reportée. Le cycle lui-même sait s'il est clos.
class AddCycleToCycleActions < ActiveRecord::Migration[8.1]
  def up
    add_reference :cycle_actions, :cycle, foreign_key: true, index: true
    add_column :cycle_actions, :outcome, :integer
    add_reference :cycle_actions, :deferred_from, foreign_key: { to_table: :cycle_actions }, index: true
    add_column :cycle_actions, :deferral_count, :integer, default: 0, null: false
    add_index :cycle_actions, [:cycle_id, :human_id]
    add_column :cycles, :closed_at, :datetime

    backfill
  end

  def down
    remove_column :cycles, :closed_at
    remove_index :cycle_actions, [:cycle_id, :human_id]
    remove_column :cycle_actions, :deferral_count
    remove_reference :cycle_actions, :deferred_from
    remove_column :cycle_actions, :outcome
    remove_reference :cycle_actions, :cycle
  end

  private

  # Rattachement des actions existantes :
  # - archivées → le cycle qui couvre `archived_at`, sinon le dernier cycle
  #   commencé avant l'archivage ;
  # - vivantes → le cycle couvrant aujourd'hui, sinon le prochain à venir,
  #   sinon le plus récent.
  # Les actions supprimées (deleted_at) sont rattachées de la même façon pour
  # ne laisser aucune ligne orpheline.
  def backfill
    cycles = select_all("SELECT id, start_date, end_date FROM cycles WHERE deleted_at IS NULL ORDER BY start_date").to_a
    return if cycles.empty?

    today = Date.current
    reference = cycles.find { |c| Date.parse(c["start_date"].to_s) <= today && Date.parse(c["end_date"].to_s) >= today }
    reference ||= cycles.find { |c| Date.parse(c["start_date"].to_s) > today }
    reference ||= cycles.last

    rows = select_all("SELECT id, archived_at, completed FROM cycle_actions").to_a
    rows.each do |row|
      cycle_id =
        if row["archived_at"]
          at = Time.zone.parse(row["archived_at"].to_s).to_date
          covering = cycles.find { |c| Date.parse(c["start_date"].to_s) <= at && Date.parse(c["end_date"].to_s) >= at }
          before = cycles.select { |c| Date.parse(c["start_date"].to_s) <= at }.last
          (covering || before || reference)["id"]
        else
          reference["id"]
        end
      outcome = row["archived_at"] ? (row["completed"] ? 0 : 2) : nil
      execute "UPDATE cycle_actions SET cycle_id = #{cycle_id.to_i}, outcome = #{outcome.nil? ? 'NULL' : outcome} WHERE id = #{row['id'].to_i}"
    end
  end
end
