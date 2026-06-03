class AddStayToPayments < ActiveRecord::Migration[7.0]
  # Étape additive et réversible (issue #26, fondation) : on dénormalise un lien
  # direct Payment -> Stay, sans toucher à `booking_id` (qui reste NOT NULL) ni
  # supprimer le Booking « ancre ». Le retrait du Booking fantôme et le passage
  # de `booking_id` en nullable feront l'objet d'un travail ultérieur (cf. issue).
  def up
    add_column :payments, :stay_id, :bigint
    add_index :payments, :stay_id
    add_foreign_key :payments, :stays, column: :stay_id

    # Backfill : chaque Payment hérite du Stay de son Booking via stay_items
    # (item vivant uniquement). Robuste, indépendant des scopes applicatifs.
    execute(<<~SQL)
      UPDATE payments
         SET stay_id = si.stay_id
        FROM stay_items si
       WHERE si.bookable_type = 'Booking'
         AND si.bookable_id   = payments.booking_id
         AND si.deleted_at IS NULL
         AND payments.stay_id IS NULL
    SQL
  end

  def down
    remove_foreign_key :payments, column: :stay_id
    remove_index :payments, :stay_id
    remove_column :payments, :stay_id
  end
end
