# Le relevé mensuel de dépôt-vente (epic #248, décision 2).
#
# Une période = un artisan = un relevé, et le jeton est ce qui permet à l'artisan
# de déclarer ses ventes depuis son téléphone sans compte dans Claudy. Les trois
# totaux sont FIGÉS à la vérification (phase 3) : ce qu'on paie doit rester ce
# qu'on a vérifié, même si le taux du contrat change l'année suivante.
class CreateConsignmentReports < ActiveRecord::Migration[8.1]
  def change
    create_table :consignment_reports do |t|
      t.references :consignor, null: false, foreign_key: true
      t.date :period_month, null: false
      t.string :status, null: false, default: "requested"
      t.string :token, null: false
      t.integer :gross_cents, null: false, default: 0
      t.integer :commission_cents, null: false, default: 0
      t.integer :net_cents, null: false, default: 0
      t.datetime :requested_at
      t.datetime :declared_at
      t.datetime :verified_at
      t.references :verified_by, foreign_key: { to_table: :users }
      t.text :notes
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :consignment_reports, :token, unique: true
    add_index :consignment_reports, :deleted_at
    add_index :consignment_reports, %i[consignor_id period_month], unique: true,
              where: "deleted_at IS NULL", name: "index_consignment_reports_on_consignor_and_month"

    create_table :consignment_report_lines do |t|
      t.references :consignment_report, null: false, foreign_key: true,
                   index: { name: "index_consignment_lines_on_report" }
      t.string :label, null: false
      t.integer :quantity, null: false, default: 1
      t.integer :unit_price_cents, null: false, default: 0
      t.integer :amount_cents, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :consignment_report_lines, :deleted_at,
              name: "index_consignment_lines_on_deleted_at"
  end
end
