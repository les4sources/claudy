class AddRefusalReasonToExperienceBookings < ActiveRecord::Migration[7.0]
  # Epic #55 — Phase 2 : validation des activités par les porteurs.
  # Le statut `refused` est une nouvelle valeur applicative de la colonne
  # `status` (pas de contrainte SQL à ajouter). Un refus exige toujours une
  # raison : d'où cette colonne texte. Nullable — les `ExperienceBooking`
  # existants (pending/confirmed/cancelled) restent valides sans raison.
  def up
    add_column :experience_bookings, :refusal_reason, :text
  end

  def down
    remove_column :experience_bookings, :refusal_reason
  end
end
