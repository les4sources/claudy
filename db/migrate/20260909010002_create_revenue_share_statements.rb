# Issue #247 — le relevé d'une période. Décision 2 : les montants sont FIGÉS à
# l'émission, et l'unicité (accord, début de période) interdit d'émettre deux
# fois le même trimestre.
class CreateRevenueShareStatements < ActiveRecord::Migration[8.1]
  def change
    create_table :revenue_share_statements do |t|
      t.references :revenue_share_agreement, null: false, foreign_key: true,
                                             index: { name: "index_rss_on_agreement_id" }
      t.date   :period_from, null: false
      t.date   :period_to,   null: false
      t.bigint :base_cents,  null: false, default: 0
      t.bigint :share_cents, null: false, default: 0
      t.string :status, null: false, default: "draft"
      t.string :token,  null: false
      t.datetime :issued_at
      t.datetime :sent_at
      t.date     :paid_on
      t.datetime :posted_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :revenue_share_statements, :token, unique: true
    add_index :revenue_share_statements, :deleted_at
    add_index :revenue_share_statements, %i[revenue_share_agreement_id period_from],
              unique: true, name: "index_rss_on_agreement_and_period"
  end
end
