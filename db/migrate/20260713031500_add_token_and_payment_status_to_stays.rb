class AddTokenAndPaymentStatusToStays < ActiveRecord::Migration[7.0]
  # Phase 1 de l'epic #26 : le Stay devient l'objet public et l'ancre de statut
  # de paiement. Additive et réversible — Booking garde son token et son
  # payment_status tant qu'il existe.
  def up
    add_column :stays, :token, :string
    add_column :stays, :payment_status, :string, default: "pending", null: false

    say_with_time "backfill stays.token" do
      select_values("SELECT id FROM stays WHERE token IS NULL").each do |id|
        execute("UPDATE stays SET token = #{quote(SecureRandom.urlsafe_base64(20))} WHERE id = #{id.to_i}")
      end
    end

    add_index :stays, :token, unique: true

    # payment_status dérivé des paiements déjà encaissés. Un paiement compte pour
    # le séjour s'il pointe directement dessus (stay_id, posé par la fondation
    # PR #30) ou s'il pointe sur un Booking rattaché au séjour. Sous-requête
    # corrélée : un même paiement ne peut pas être compté deux fois, même quand
    # le séjour porte plusieurs bookings.
    execute(<<~SQL)
      UPDATE stays
         SET payment_status = CASE
               WHEN paid.cents > 0 AND paid.cents >= stays.total_amount_cents THEN 'paid'
               WHEN paid.cents > 0 THEN 'partially_paid'
               ELSE 'pending'
             END
        FROM (
          SELECT s.id AS stay_id,
                 COALESCE((
                   SELECT SUM(p.amount_cents)
                     FROM payments p
                    WHERE p.status = 'paid'
                      AND p.deleted_at IS NULL
                      AND (p.stay_id = s.id
                           OR p.booking_id IN (
                                SELECT si.bookable_id
                                  FROM stay_items si
                                 WHERE si.stay_id = s.id
                                   AND si.bookable_type = 'Booking'
                                   AND si.deleted_at IS NULL))
                 ), 0) AS cents
            FROM stays s
        ) AS paid
       WHERE paid.stay_id = stays.id
    SQL
  end

  def down
    remove_index :stays, :token
    remove_column :stays, :payment_status
    remove_column :stays, :token
  end
end
