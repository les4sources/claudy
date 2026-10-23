# Services annexes d'un séjour (Michael, 2026-10-23) : le prêt d'un set de
# disc-golf, et ce qui viendra. Une ligne = un libellé et un montant, tapés à
# la main ou repris d'un service du catalogue (/services). Elles s'ajoutent au
# total du séjour, comme le bar.
#
# Le service du catalogue peut porter son compte de recette (700006 Location
# discogolf) : la ventilation d'un paiement du séjour le reprend. Une ligne
# tapée sans service tombe sur la catégorie « services » de `RevenueMapping`.
class CreateStayServiceLines < ActiveRecord::Migration[8.1]
  def up
    add_reference :services, :general_account, foreign_key: true, null: true

    create_table :stay_service_lines do |t|
      t.references :stay, null: false, foreign_key: true
      t.references :service, foreign_key: true, null: true
      t.references :general_account, foreign_key: true, null: true
      t.string :label, null: false
      t.integer :amount_cents, null: false, default: 0
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :stay_service_lines, :deleted_at

    # Le repli des lignes tapées à la main : le compte des locations
    # d'hébergement, comme le camping ou les hamacs, tant que le collectif
    # n'a pas choisi mieux.
    execute <<~SQL
      INSERT INTO revenue_mappings (category, general_account_id, created_at, updated_at)
      SELECT 'services', id, NOW(), NOW() FROM general_accounts
      WHERE code = '700000' AND deleted_at IS NULL
        AND NOT EXISTS (SELECT 1 FROM revenue_mappings WHERE category = 'services')
      LIMIT 1
    SQL
  end

  def down
    execute "DELETE FROM revenue_mappings WHERE category = 'services'"
    drop_table :stay_service_lines
    remove_reference :services, :general_account, foreign_key: true
  end
end
