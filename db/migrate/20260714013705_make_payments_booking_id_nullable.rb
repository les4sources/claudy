class MakePaymentsBookingIdNullable < ActiveRecord::Migration[7.0]
  # Epic #26, Phase 2 : un séjour sans hébergement n'a plus de Booking fantôme,
  # donc son Payment n'a pas de booking_id. La colonne NOT NULL le rendait
  # impossible.
  #
  # Cette migration était planifiée en Phase 4 (« verrouillage »), mais la Phase 2
  # ne peut pas tenir son critère « séjour sans hébergement → aucun Booking créé,
  # paiement rattaché au Stay » sans elle. Elle est purement permissive : aucun
  # Payment existant n'est touché. La Phase 4 garde le reste de son périmètre
  # (validation de présence de stay_id, verify_stay_links à 100 %, simplification
  # de Stay#payments).
  def up
    change_column_null :payments, :booking_id, true
  end

  def down
    change_column_null :payments, :booking_id, false
  end
end
