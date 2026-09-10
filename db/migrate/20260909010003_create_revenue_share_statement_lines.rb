# Issue #247 — les lignes du relevé.
#
# L'index unique partiel sur `booking_id WHERE kind = 'booking'` est l'invariant
# du lot : une réservation n'est relevée qu'UNE fois. La régularisation
# (décision 5) est d'un autre `kind` — elle porte la différence de prix apparue
# après coup et référence la ligne d'origine, elle ne re-relève pas la nuitée.
class CreateRevenueShareStatementLines < ActiveRecord::Migration[8.1]
  def change
    create_table :revenue_share_statement_lines do |t|
      t.references :revenue_share_statement, null: false, foreign_key: true,
                                             index: { name: "index_rssl_on_statement_id" }
      t.references :booking, null: false, foreign_key: true
      t.references :origin_line, foreign_key: { to_table: :revenue_share_statement_lines }
      t.string  :kind, null: false, default: "booking"
      t.date    :from_date
      t.date    :to_date
      t.string  :label
      t.bigint  :amount_cents, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :revenue_share_statement_lines, :deleted_at
    add_index :revenue_share_statement_lines, :booking_id,
              unique: true, where: "kind = 'booking' AND deleted_at IS NULL",
              name: "index_rssl_unique_booking_once"
  end
end
