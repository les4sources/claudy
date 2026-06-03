class CreateBookingPageViews < ActiveRecord::Migration[7.0]
  def change
    create_table :booking_page_views do |t|
      t.references :booking, null: false, foreign_key: true, index: true
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end
  end
end
