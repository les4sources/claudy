class AddBundleReferencesToTasks < ActiveRecord::Migration[7.0]
  def change
    add_reference :tasks, :bundle, null: false, foreign_key: true
  end
end
