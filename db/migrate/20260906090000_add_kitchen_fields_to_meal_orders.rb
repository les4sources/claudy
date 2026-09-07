# Epic Cuisine (#219), phase 1 — la ligne de repas devient une DEMANDE suivie :
# qui s'en charge, où en est le client, où en est la cuisine, ce qu'elle a coûté.
class AddKitchenFieldsToMealOrders < ActiveRecord::Migration[8.1]
  def change
    change_table :meal_orders, bulk: true do |t|
      t.string   :moment                 # midi | soir | gouter (le trio couvre les trois)
      t.string   :status,     null: false, default: "requested"
      t.string   :validation, null: false, default: "pending"
      t.datetime :validated_at
      t.text     :refusal_reason
      t.text     :cancellation_reason
      t.bigint   :responsible_human_id
      t.integer  :unit_price_cents       # override du tarif €/pers, nullable
      t.text     :notes                  # intolérances, précisions, menu
      t.integer  :cost_cents             # coût réel, saisi après coup
      t.text     :cost_notes
      t.datetime :bread_reminder_sent_at
    end

    add_index :meal_orders, :status
    add_index :meal_orders, :validation
    add_index :meal_orders, :responsible_human_id
    add_foreign_key :meal_orders, :humans, column: :responsible_human_id
  end
end
