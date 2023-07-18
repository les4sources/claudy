class CreateTasks < ActiveRecord::Migration[7.0]
  def change
    create_table :tasks do |t|
      t.string :name
      t.references :project, null: false, foreign_key: true
      t.text :description
      t.string :status
      t.date :due_date
      t.timestamp :deleted_at

      t.timestamps
    end
  end
end
