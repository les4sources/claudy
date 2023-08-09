class CreateBundles < ActiveRecord::Migration[7.0]
  def change
    create_table :bundles do |t|
      t.string :name
      t.integer :position
      t.references :project, null: true, foreign_key: true
      t.references :team, null: true, foreign_key: true
      t.datetime :deleted_at

      t.timestamps
    end

    # Create default bundles for projects
    Project.all.each do |project|
      Bundle.create!(name: 'Actions du projet', position: 0, project: project)
    end

    # Create default bundles for teams
    Team.all.each do |team|
      Bundle.create!(name: 'Actions du pôle', position: 0, team: team)
    end
  end
end
