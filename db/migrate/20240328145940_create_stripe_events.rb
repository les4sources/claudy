class CreateStripeEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :stripe_events do |t|
      t.string :webhook_id
      t.string :event_type
      t.string :object_id

      t.timestamps
    end
  end
end
