# Epic #244, phase 1 — ce qu'il faut pour rémunérer un porteur d'activité :
# le pôle qui portera la charge, le tarif horaire (surcharge facultative du
# tarif général `activity.carrier_hourly`) et le montant FIGÉ sur la
# réservation au moment de sa confirmation.
class AddCarrierPayToExperiences < ActiveRecord::Migration[8.1]
  def change
    add_reference :experiences, :team, foreign_key: true
    add_column :experiences, :carrier_hourly_rate_cents, :integer
    # Figé à la confirmation (décision 2) : un changement de tarif ultérieur ne
    # réécrit jamais le passé.
    add_column :experience_bookings, :carrier_fee_cents, :integer
  end
end
