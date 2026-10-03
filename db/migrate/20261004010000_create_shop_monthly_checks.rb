# Le contrôle mensuel des carnets Épicerie et Boulangerie (epic #359, phase 5) :
# trois totaux saisis par mois, et l'écart figé à la validation, comme un
# comptage de caisse.
class CreateShopMonthlyChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_monthly_checks do |t|
      t.string :channel, null: false
      t.date :period_month, null: false
      t.bigint :sheets_total_cents, null: false, default: 0
      t.bigint :transfer_total_cents, null: false, default: 0
      t.bigint :cash_total_cents, null: false, default: 0
      # Figés à la validation, jamais recalculés après coup.
      t.bigint :bank_received_cents
      t.bigint :gap_cents
      t.string :sheet_numbers
      t.text :notes
      t.string :status, null: false, default: "draft"
      t.datetime :validated_at
      t.references :validated_by, foreign_key: { to_table: :users }
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :shop_monthly_checks, %i[channel period_month], unique: true, where: "deleted_at IS NULL",
                                                               name: "index_shop_monthly_checks_on_channel_and_month"
    add_index :shop_monthly_checks, :deleted_at
  end
end
