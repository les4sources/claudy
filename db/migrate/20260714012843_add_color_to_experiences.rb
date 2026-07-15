class AddColorToExperiences < ActiveRecord::Migration[7.0]
  # Une couleur par activité (epic #25, Phase 5) : c'est elle qui distingue les
  # créneaux des différentes activités sur le calendrier global de l'index, où
  # les activités ont le droit de se chevaucher.
  def up
    add_column :experiences, :color, :string

    # Backfill : on répartit la palette dans l'ordre plutôt que de tirer au
    # hasard, pour éviter que deux activités tombent sur la même couleur.
    palette = Experience::PALETTE
    Experience.unscoped.order(:id).pluck(:id).each_with_index do |id, index|
      Experience.unscoped.where(id: id).update_all(color: palette[index % palette.size])
    end
  end

  def down
    remove_column :experiences, :color
  end
end
