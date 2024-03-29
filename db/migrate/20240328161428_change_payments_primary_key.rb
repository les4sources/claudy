class ChangePaymentsPrimaryKey < ActiveRecord::Migration[7.0]
  def change
    rename_column :payments, :id, :numeric_id
    rename_column :payments, :uuid, :id
    execute "ALTER TABLE payments DROP CONSTRAINT payments_pkey;"
    execute "ALTER TABLE payments ADD PRIMARY KEY (id);"
  end
end
