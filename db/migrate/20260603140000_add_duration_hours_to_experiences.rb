class AddDurationHoursToExperiences < ActiveRecord::Migration[7.0]
  def change
    # Durée numérique en heures (ex. 1 / 2 / 2.5 / 3 / 4) qui pilotera la taille
    # des blocs de disponibilité (Phase 4). Le champ texte `duration` existant
    # reste un libellé libre (épic #25, décision produit).
    add_column :experiences, :duration_hours, :decimal, precision: 4, scale: 2
  end
end
