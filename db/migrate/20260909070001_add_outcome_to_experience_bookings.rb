# Epic #244, phase 2 — la tenue de l'activité.
#
# Une activité confirmée n'est pas une activité TENUE. Entre les deux il y a le
# jour J, et parfois personne ne vient. Sans cette distinction, le relevé de
# rémunération de la phase 3 paierait des créneaux qui n'ont pas eu lieu — et
# c'est exactement le genre d'erreur qu'on ne découvre qu'au moment de payer.
#
# `outcome_recorded_by_id` pointe un `Human`, pas un `User` : les postes sont
# partagés sous des comptes communs, et retomber sur le compte connecté
# désignerait le poste, pas la personne qui a répondu.
class AddOutcomeToExperienceBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :experience_bookings, :outcome, :string
    add_column :experience_bookings, :outcome_recorded_at, :datetime
    add_reference :experience_bookings, :outcome_recorded_by,
                  foreign_key: { to_table: :humans }, null: true

    add_index :experience_bookings, :outcome
  end
end
