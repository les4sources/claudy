class CreateJoinTableTaskHuman < ActiveRecord::Migration[7.0]
  def change
    create_join_table :tasks, :humans do |t|
      t.index [:task_id, :human_id]
      t.index [:human_id, :task_id]
    end
  end
end
